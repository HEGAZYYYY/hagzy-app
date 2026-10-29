import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import * as crypto from "crypto";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

// Secret defined in Firebase Secret Manager
export const paymentWebhookSecret = defineSecret("PAYMENT_WEBHOOK_SECRET");

// Types
export type PaymentMethod = "INSTAPAY" | "MOBILE_WALLET";

export interface CreatePaymentIntentRequest {
  bookingId: string;
  paymentMethod: PaymentMethod;
  senderIdentifier: string;
}

export interface WebhookPaymentPayload {
  eventId: string;
  paymentMethod: PaymentMethod;
  senderIdentifier: string;
  amount: number;
  providerRef: string | null;
  rawText: string;
  timestamp?: number | string;
}

/**
 * Normalizes sender identifiers for exact matching:
 * - INSTAPAY: lowercased, stripped extra @instapay suffixes, trimmed -> 'user@instapay'
 * - MOBILE_WALLET: 11-digit Egyptian phone number -> '010XXXXXXXX'
 */
export function normalizeSenderIdentifier(method: PaymentMethod, raw: string): string {
  if (!raw || typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "Sender identifier is required.");
  }

  const trimmed = raw.trim();

  if (method === "INSTAPAY") {
    let handle = trimmed.toLowerCase();
    // Remove any trailing @instapay or spaces
    handle = handle.replace(/(@instapay)+$/gi, "").trim();
    // Strip illegal characters
    handle = handle.replace(/[^a-z0-9_.-]/g, "");
    if (!handle) {
      throw new HttpsError("invalid-argument", "Invalid InstaPay address format.");
    }
    return `${handle}@instapay`;
  } else if (method === "MOBILE_WALLET") {
    // Strip whitespace, dashes, plus, parenthesis
    let phone = trimmed.replace(/[\s\-\+\(\)]/g, "");
    // Remove leading international prefix: +20 or 0020 or 20
    if (phone.startsWith("0020")) {
      phone = phone.substring(4);
    } else if (phone.startsWith("20")) {
      phone = phone.substring(2);
    }
    // If it started without leading 0 (e.g. 1012345678), prepend 0
    if (phone.length === 10 && /^[125]\d{8}$/.test(phone)) {
      phone = `0${phone}`;
    }

    const egPhoneRegex = /^01[0125]\d{8}$/;
    if (!egPhoneRegex.test(phone)) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid Egyptian mobile wallet number. Must be an 11-digit number starting with 010, 011, 012, or 015."
      );
    }
    return phone;
  }

  throw new HttpsError("invalid-argument", `Unsupported payment method: ${method}`);
}

/**
 * Helper to update booking status across root and user subcollection
 */
async function markBookingAsPaid(
  transaction: admin.firestore.Transaction,
  bookingId: string,
  userId: string,
  paymentMethod: string,
  amount: number,
  refId: string
) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const updatePayload = {
    status: "CONFIRMED",
    payment_status: "PAID",
    payment_method: paymentMethod,
    paid_amount: amount,
    payment_verified_at: now,
    payment_reference: refId,
    updated_at: now,
  };

  // 1. Root collection booking if it exists
  const rootBookingRef = db.collection("bookings").doc(bookingId);
  const rootSnap = await transaction.get(rootBookingRef);
  if (rootSnap.exists) {
    transaction.update(rootBookingRef, updatePayload);
  }

  // 2. User subcollection: users/{userId}/bookings/{bookingId}
  if (userId) {
    const userBookingRef = db.collection("users").doc(userId).collection("bookings").doc(bookingId);
    const userBookingSnap = await transaction.get(userBookingRef);
    if (userBookingSnap.exists) {
      transaction.update(userBookingRef, updatePayload);
    }
  }
}

/**
 * 1. createOrUpdatePaymentIntent (Callable Cloud Function v2)
 * Creates or updates an active payment intent, guards against collisions,
 * and performs retroactive match against incoming payment events from the past 15 minutes.
 */
export const createOrUpdatePaymentIntent = onCall<CreatePaymentIntentRequest>(
  { cors: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "User must be authenticated.");
    }

    const { bookingId, paymentMethod, senderIdentifier } = request.data;
    if (!bookingId || !paymentMethod || !senderIdentifier) {
      throw new HttpsError(
        "invalid-argument",
        "bookingId, paymentMethod, and senderIdentifier are required."
      );
    }

    if (paymentMethod !== "INSTAPAY" && paymentMethod !== "MOBILE_WALLET") {
      throw new HttpsError("invalid-argument", "paymentMethod must be INSTAPAY or MOBILE_WALLET.");
    }

    const normalizedSender = normalizeSenderIdentifier(paymentMethod, senderIdentifier);

    // Fetch authoritative booking data to determine amount
    let authoritativeAmount = 0;
    let bookingOwnerUid = uid;

    const rootBookingRef = db.collection("bookings").doc(bookingId);
    const rootBookingSnap = await rootBookingRef.get();

    if (rootBookingSnap.exists) {
      const data = rootBookingSnap.data()!;
      authoritativeAmount = Number(data.depositAmount ?? data.totalPrice ?? data.amount ?? data.price ?? 0);
      bookingOwnerUid = data.userId || data.user_id || uid;
      if (data.status === "CONFIRMED" || data.payment_status === "PAID") {
        throw new HttpsError("failed-precondition", "This booking is already paid and confirmed.");
      }
    } else {
      // Check user subcollection: users/{uid}/bookings/{bookingId}
      const userBookingRef = db.collection("users").doc(uid).collection("bookings").doc(bookingId);
      const userBookingSnap = await userBookingRef.get();
      if (!userBookingSnap.exists) {
        throw new HttpsError("not-found", `Booking with ID ${bookingId} not found.`);
      }
      const data = userBookingSnap.data()!;
      authoritativeAmount = Number(data.depositAmount ?? data.totalPrice ?? data.amount ?? data.price ?? 0);
      if (data.status === "CONFIRMED" || data.payment_status === "PAID") {
        throw new HttpsError("failed-precondition", "This booking is already paid and confirmed.");
      }
    }

    if (!authoritativeAmount || authoritativeAmount <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "Invalid or zero booking amount. Cannot initiate payment."
      );
    }

    const intentId = `intent_${bookingId}_${paymentMethod.toLowerCase()}`;
    const intentRef = db.collection("payment_intents").doc(intentId);

    return await db.runTransaction(async (transaction) => {
      const now = admin.firestore.Timestamp.now();
      const expiresAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + 10 * 60 * 1000); // 10 minutes
      const fifteenMinutesAgo = admin.firestore.Timestamp.fromMillis(now.toMillis() - 15 * 60 * 1000);

      // Collision Guard: Ensure no other booking has an active AWAITING_TRANSFER intent for this exact sender & amount
      const activeCollisionQuery = db
        .collection("payment_intents")
        .where("payment_method", "==", paymentMethod)
        .where("expected_sender_identifier", "==", normalizedSender)
        .where("expected_amount", "==", authoritativeAmount)
        .where("status", "==", "AWAITING_TRANSFER")
        .where("expires_at", ">", now);

      const collisionSnap = await transaction.get(activeCollisionQuery);
      for (const doc of collisionSnap.docs) {
        if (doc.id !== intentId && doc.data().booking_id !== bookingId) {
          throw new HttpsError(
            "already-exists",
            "Another pending booking is currently awaiting payment from this identifier for this exact amount. " +
              "Please wait 10 minutes or use a different account/number."
          );
        }
      }

      // Retroactive Match Check: Check if an unclaimed payment event already arrived in the last 15 minutes
      const retroactiveQuery = db
        .collection("incoming_payment_events")
        .where("payment_method", "==", paymentMethod)
        .where("sender_identifier", "==", normalizedSender)
        .where("amount", "==", authoritativeAmount)
        .where("is_claimed", "==", false)
        .where("received_at", ">=", fifteenMinutesAgo)
        .orderBy("received_at", "asc")
        .limit(1);

      const eventSnap = await transaction.get(retroactiveQuery);

      if (!eventSnap.empty) {
        const matchedEventDoc = eventSnap.docs[0];
        const matchedEventData = matchedEventDoc.data();

        // 1. Claim event
        transaction.update(matchedEventDoc.ref, {
          is_claimed: true,
          claimed_by_intent_id: intentId,
          claimed_by_booking_id: bookingId,
          claimed_at: now,
        });

        // 2. Mark intent as VERIFIED
        const intentPayload = {
          booking_id: bookingId,
          user_id: uid,
          payment_method: paymentMethod,
          expected_sender_identifier: normalizedSender,
          expected_amount: authoritativeAmount,
          status: "VERIFIED",
          expires_at: expiresAt,
          verified_at: now,
          matched_event_id: matchedEventDoc.id,
          created_at: now,
          updated_at: now,
        };
        transaction.set(intentRef, intentPayload, { merge: true });

        // 3. Mark booking as PAID & CONFIRMED
        await markBookingAsPaid(
          transaction,
          bookingId,
          bookingOwnerUid,
          paymentMethod,
          authoritativeAmount,
          matchedEventData.provider_ref || matchedEventDoc.id
        );

        logger.info(
          `[Retroactive Match] Booking ${bookingId} verified immediately with event ${matchedEventDoc.id}`
        );

        return {
          intentId,
          status: "VERIFIED",
          expiresAt: expiresAt.toDate().toISOString(),
          verifiedAt: now.toDate().toISOString(),
          expectedAmount: authoritativeAmount,
          expectedSenderIdentifier: normalizedSender,
          matchedEventId: matchedEventDoc.id,
        };
      }

      // If no retroactive match: create or update intent in AWAITING_TRANSFER status
      const intentPayload = {
        booking_id: bookingId,
        user_id: uid,
        payment_method: paymentMethod,
        expected_sender_identifier: normalizedSender,
        expected_amount: authoritativeAmount,
        status: "AWAITING_TRANSFER",
        expires_at: expiresAt,
        verified_at: null,
        matched_event_id: null,
        created_at: now,
        updated_at: now,
      };
      transaction.set(intentRef, intentPayload, { merge: true });

      logger.info(`[Intent Created] Booking ${bookingId} awaiting transfer from ${normalizedSender}`);

      return {
        intentId,
        status: "AWAITING_TRANSFER",
        expiresAt: expiresAt.toDate().toISOString(),
        verifiedAt: null,
        expectedAmount: authoritativeAmount,
        expectedSenderIdentifier: normalizedSender,
        matchedEventId: null,
      };
    });
  }
);

/**
 * 2. paymentGatewayWebhook (HTTP Webhook v2 with HMAC-SHA256 signature verification)
 * Receives signed webhooks from the dedicated Android phone oracle for InstaPay and Wallet SMS.
 */
export const paymentGatewayWebhook = onRequest(
  { secrets: [paymentWebhookSecret] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed. Use POST." });
      return;
    }

    const signature = req.headers["x-webhook-signature"] as string | undefined;
    if (!signature) {
      logger.warn("[Webhook] Missing X-Webhook-Signature header.");
      res.status(401).json({ error: "Missing signature header." });
      return;
    }

    // Verify HMAC-SHA256 Signature
    const secret = paymentWebhookSecret.value();
    if (!secret) {
      logger.error("[Webhook] PAYMENT_WEBHOOK_SECRET is not configured.");
      res.status(500).json({ error: "Webhook secret not configured on server." });
      return;
    }

    // Use rawBody if available, otherwise serialize body
    const rawPayload = (req as any).rawBody
      ? (req as any).rawBody.toString("utf8")
      : JSON.stringify(req.body);

    const expectedSignature = crypto
      .createHmac("sha256", secret)
      .update(rawPayload)
      .digest("hex");

    const sigBuffer = Buffer.from(signature, "hex");
    const expectedBuffer = Buffer.from(expectedSignature, "hex");

    if (sigBuffer.length !== expectedBuffer.length || !crypto.timingSafeEqual(sigBuffer, expectedBuffer)) {
      logger.warn("[Webhook] Invalid HMAC signature detected.");
      res.status(403).json({ error: "Invalid signature." });
      return;
    }

    const payload = req.body as WebhookPaymentPayload;
    const { eventId, paymentMethod, senderIdentifier, amount, providerRef, rawText } = payload;

    if (!eventId || !paymentMethod || !senderIdentifier || amount === undefined || amount === null) {
      res.status(400).json({ error: "Missing required fields in payload." });
      return;
    }

    const normalizedSender = normalizeSenderIdentifier(paymentMethod, senderIdentifier);
    const parsedAmount = Number(amount);
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      res.status(400).json({ error: "Invalid amount value." });
      return;
    }

    const eventDocRef = db.collection("incoming_payment_events").doc(eventId);

    try {
      const result = await db.runTransaction(async (transaction) => {
        const now = admin.firestore.Timestamp.now();

        // 1. Idempotency Check by Document ID
        const existingEventSnap = await transaction.get(eventDocRef);
        if (existingEventSnap.exists) {
          logger.info(`[Webhook Idempotent] Event ID ${eventId} already recorded.`);
          return {
            status: "DUPLICATE",
            message: "Event ID already processed.",
            matched: existingEventSnap.data()?.is_claimed ?? false,
          };
        }

        // 2. Idempotency Check by providerRef (if available)
        if (providerRef && typeof providerRef === "string" && providerRef.trim().length > 0) {
          const providerQuery = db
            .collection("incoming_payment_events")
            .where("provider_ref", "==", providerRef.trim())
            .limit(1);

          const providerSnap = await transaction.get(providerQuery);
          if (!providerSnap.empty) {
            logger.info(`[Webhook Idempotent] Provider ref ${providerRef} already recorded.`);
            return {
              status: "DUPLICATE",
              message: "Provider reference already processed.",
              matched: true,
            };
          }
        }

        // 3. Query payment_intents for matching active intent
        const intentQuery = db
          .collection("payment_intents")
          .where("payment_method", "==", paymentMethod)
          .where("expected_sender_identifier", "==", normalizedSender)
          .where("expected_amount", "==", parsedAmount)
          .where("status", "==", "AWAITING_TRANSFER")
          .where("expires_at", ">", now)
          .orderBy("expires_at", "asc")
          .limit(1);

        const intentSnap = await transaction.get(intentQuery);

        if (!intentSnap.empty) {
          // MATCH FOUND!
          const matchedIntentDoc = intentSnap.docs[0];
          const matchedIntentData = matchedIntentDoc.data();
          const bookingId = matchedIntentData.booking_id;
          const userId = matchedIntentData.user_id;

          // A. Save event document as CLAIMED
          transaction.set(eventDocRef, {
            event_id: eventId,
            payment_method: paymentMethod,
            sender_identifier: normalizedSender,
            amount: parsedAmount,
            provider_ref: providerRef || null,
            raw_text: rawText || "",
            is_claimed: true,
            claimed_by_intent_id: matchedIntentDoc.id,
            claimed_by_booking_id: bookingId,
            received_at: now,
          });

          // B. Update payment_intent to VERIFIED
          transaction.update(matchedIntentDoc.ref, {
            status: "VERIFIED",
            verified_at: now,
            matched_event_id: eventId,
            updated_at: now,
          });

          // C. Update booking to CONFIRMED
          await markBookingAsPaid(
            transaction,
            bookingId,
            userId,
            paymentMethod,
            parsedAmount,
            providerRef || eventId
          );

          logger.info(
            `[Webhook Match] Successfully verified booking ${bookingId} via intent ${matchedIntentDoc.id}`
          );

          return {
            status: "MATCHED_AND_VERIFIED",
            bookingId,
            intentId: matchedIntentDoc.id,
            matched: true,
          };
        } else {
          // NO MATCH YET -> Record as UNCLAIMED for retroactive match within next 15 minutes
          transaction.set(eventDocRef, {
            event_id: eventId,
            payment_method: paymentMethod,
            sender_identifier: normalizedSender,
            amount: parsedAmount,
            provider_ref: providerRef || null,
            raw_text: rawText || "",
            is_claimed: false,
            claimed_by_intent_id: null,
            claimed_by_booking_id: null,
            received_at: now,
          });

          logger.info(
            `[Webhook Stored Unclaimed] Saved event ${eventId} from ${normalizedSender} (${parsedAmount} EGP)`
          );

          return {
            status: "STORED_UNCLAIMED",
            eventId,
            matched: false,
          };
        }
      });

      res.status(200).json({ success: true, ...result });
    } catch (err: any) {
      logger.error("[Webhook Error] Transaction error:", err);
      res.status(500).json({ error: "Internal server error processing payment event." });
    }
  }
);


import { Hono } from '@hono/hono';
import { getEnv } from './_shared/db.ts';

export interface GeneratedVenueSpace {
  name: string;
  kind: string;
  hourlyRate: number;
}

export interface GeneratedVenueService {
  name: string;
  price: number;
}

export interface GeneratedVenuePayload {
  name: string;
  type: 'sports' | 'salon' | 'lounge';
  category: string;
  city: string;
  address: string;
  description: string;
  openHour: number;
  closeHour: number;
  depositPercent: number;
  instaPayAddress: string;
  vodafoneCashNumber: string;
  amenities: string[];
  spaces: GeneratedVenueSpace[];
  services: GeneratedVenueService[];
}

export function buildFallbackVenueFromTemplate(
  prompt: string,
  categoryHint: string = 'padel',
  isArabic: boolean = false
): GeneratedVenuePayload {
  const lower = (prompt + ' ' + categoryHint).toLowerCase();

  // 1. Detect Category & Vertical Type
  let type: 'sports' | 'salon' | 'lounge' = 'sports';
  let category = 'padel';

  if (/صالون|حلاقة|حلاق|كوافير|تجميل|شعر|salon|barber|grooming|hair/i.test(lower)) {
    type = 'salon';
    category = 'salon';
  } else if (/playstation|بلايستيشن|ps5|ps4|جيمنج|gaming/i.test(lower)) {
    type = 'lounge';
    category = 'playstation';
  } else if (/بلياردو|billiards|pool|snooker/i.test(lower)) {
    type = 'lounge';
    category = 'billiards';
  } else if (/كرة|كورة|football|خماسي|ملعب كرة/i.test(lower)) {
    type = 'sports';
    category = 'football';
  } else if (/تنس|tennis/i.test(lower)) {
    type = 'sports';
    category = 'tennis';
  } else {
    type = 'sports';
    category = 'padel';
  }

  // 2. Extract Phone / Wallet
  const phoneMatch = prompt.match(/01[0125][0-9]{8}/);
  const phone = phoneMatch ? phoneMatch[0] : '';

  // 3. Extract InstaPay Handle
  const ipaMatch = prompt.match(/([a-zA-Z0-9._-]+@instapay)/i);
  const instaPay = ipaMatch ? ipaMatch[1] : '';

  // 4. Extract Deposit % (default 25%)
  const depMatch = prompt.match(/(?:عربون|deposit)[:\s]+([0-9]{1,3})%?/i) || prompt.match(/([0-9]{1,3})%\s*(?:عربون|deposit)/i);
  const depositPercent = depMatch ? Math.max(0, Math.min(100, Number(depMatch[1]))) : 25;

  // 5. Extract Explicit Price if mentioned
  const priceMatch = prompt.match(/(?:الساعة|ساعة|price|rate|بـ|ب|بقيمة)[:\s]*([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|egp|le)?/i);
  const extractedPrice = priceMatch ? Number(priceMatch[1]) : 0;

  // 6. Extract City
  let city = isArabic ? 'القاهرة الجديدة' : 'New Cairo';
  if (/تجمع|التجمع/i.test(lower)) city = isArabic ? 'التجمع الخامس' : 'New Cairo';
  else if (/معادي|المعادي|maadi/i.test(lower)) city = isArabic ? 'المعادي' : 'Maadi';
  else if (/زايد|الشيخ زايد|zayed/i.test(lower)) city = isArabic ? 'الشيخ زايد' : 'Sheikh Zayed';
  else if (/أكتوبر|اكتوبر|october/i.test(lower)) city = isArabic ? 'السادس من أكتوبر' : '6th of October';
  else if (/نصر|مدينة نصر|nasr city/i.test(lower)) city = isArabic ? 'مدينة نصر' : 'Nasr City';
  else if (/إسكندرية|اسكندرية|alex/i.test(lower)) city = isArabic ? 'الإسكندرية' : 'Alexandria';
  else if (/طنطا|tanta/i.test(lower)) city = isArabic ? 'طنطا' : 'Tanta';
  else if (/كفر الشيخ|kafr el sheikh/i.test(lower)) city = isArabic ? 'كفر الشيخ' : 'Kafr El Sheikh';
  else if (/المنصورة|منصورة|mansoura/i.test(lower)) city = isArabic ? 'المنصورة' : 'Mansoura';

  // 7. Extract Venue Name or synthesize friendly name
  let name = '';
  const nameMatch = prompt.match(/(?:اسمه|اسم المكان|اسم النادي|venue|name)[:\s]+([^\n,،.]+)/i);
  if (nameMatch && nameMatch[1].trim()) {
    name = nameMatch[1].trim();
  } else {
    const cleanWords = prompt.split(/[\s,،.]+/).filter(w => w.length > 2 && !/ملعب|نادي|صالون|حجز|الساعة|عربون|جنيه|01[0125]/.test(w));
    name = cleanWords.slice(0, 3).join(' ') || (category === 'padel' ? 'Nile Padel Club' : category === 'salon' ? 'Elite Lounge & Salon' : 'Arena Hub');
  }

  // 8. Build Category-Specific Spaces & Services
  let spaces: GeneratedVenueSpace[] = [];
  let services: GeneratedVenueService[] = [];
  let amenities: string[] = [];
  let description = '';

  if (category === 'padel') {
    const rate = extractedPrice > 0 ? extractedPrice : 400;
    spaces = [
      { name: 'Court 1 (Panoramic)', kind: 'Padel', hourlyRate: rate },
      { name: 'Court 2 (Standard)', kind: 'Padel', hourlyRate: rate },
    ];
    services = [
      { name: isArabic ? 'تأجير مضرب بادل احترافي' : 'Pro Padel Racket Rental', price: 50 },
      { name: isArabic ? 'حصة تدريب فردية (ساعة)' : 'Private Coaching Session (1 hr)', price: 250 },
      { name: isArabic ? 'كرات جديدة (علبة)' : 'Fresh Ball Can (3 balls)', price: 180 },
    ];
    amenities = ['Parking', 'Showers', 'Night Floodlights', 'Wi-Fi', 'Café & Shaded Seating'];
    description = isArabic
      ? 'ملاعب بادل احترافية مجهزة بأعلى مواصفات الإضاءة والأرضيات الزجاجية مع خدمات تدريب وتأجير معدات.'
      : 'Top-tier panoramic padel courts with professional lighting, equipment rental, and certified coaching.';
  } else if (category === 'football') {
    const rate = extractedPrice > 0 ? extractedPrice : 350;
    spaces = [
      { name: 'Pitch A (5-a-side)', kind: 'Football 5x5', hourlyRate: rate },
      { name: 'Pitch B (5-a-side)', kind: 'Football 5x5', hourlyRate: rate },
    ];
    services = [
      { name: isArabic ? 'تأجير أطقم تيشرتات مميزة' : 'Team Bibs & Ball Rental', price: 40 },
      { name: isArabic ? 'حكم مباراة معتمد' : 'Certified Match Referee', price: 150 },
    ];
    amenities = ['Parking', 'Locker Rooms', 'Showers', 'Bleachers', 'Night Floodlights'];
    description = isArabic
      ? 'ملاعب كرة قدم خماسية بنجيل صناعي معتمد وترتان ممتاز وإضاءة مسائية متطورة.'
      : 'FIFA-grade turf 5-a-side football pitches with floodlights and locker facilities.';
  } else if (category === 'salon') {
    const rate = extractedPrice > 0 ? extractedPrice : 150;
    spaces = [
      { name: 'VIP Chair 1', kind: 'Master Barber', hourlyRate: rate },
      { name: 'Stylist Chair 2', kind: 'Stylist Chair', hourlyRate: Math.round(rate * 0.8) },
    ];
    services = [
      { name: isArabic ? 'قص شعر وتصفيف VIP' : 'Haircut & VIP Styling', price: 120 },
      { name: isArabic ? 'تشذيب لحية بالبخار وفوطة ساخنة' : 'Hot Towel Beard Trim & Shave', price: 90 },
      { name: isArabic ? 'جلسة تنظيف بشرة وماسك أسود' : 'Deep Facial Cleansing & Mask', price: 180 },
    ];
    amenities = ['AC', 'Wi-Fi', 'Beverages & Espresso', 'Complimentary Parking', 'VIP Room'];
    description = isArabic
      ? 'صالون متكامل يقدم خدمات الحلاقة والعناية بالبشرة بأيدي خبراء متخصصين وأجواء راقية.'
      : 'Modern premium grooming lounge offering bespoke haircuts, beard styling, and skincare treatments.';
  } else if (category === 'playstation') {
    const rate = extractedPrice > 0 ? extractedPrice : 70;
    spaces = [
      { name: 'VIP Room 1 (PS5 & 65" 4K)', kind: 'PS5 VIP Room', hourlyRate: rate },
      { name: 'Standard Station 2 (PS5)', kind: 'PS5 Standard', hourlyRate: Math.max(40, Math.round(rate * 0.75)) },
    ];
    services = [
      { name: isArabic ? 'دراع إضافي تحكم' : 'Extra Controller', price: 25 },
      { name: isArabic ? 'مشروب طاقة / قهوة' : 'Energy Drink / Specialty Coffee', price: 35 },
    ];
    amenities = ['AC', 'Ultra 4K OLED Screens', 'Surround Sound', 'High-Speed Wi-Fi', 'Snack Bar'];
    description = isArabic
      ? 'غرف بلايستيشن VIP مجهزة بأحدث أجهزة PS5 وشاشات 4K مع تكيف مركزي وأفضل ألعاب الجيل الجديد.'
      : 'Exclusive PS5 gaming lounge featuring private 4K VIP suites and the latest competitive titles.';
  } else {
    const rate = extractedPrice > 0 ? extractedPrice : 200;
    spaces = [
      { name: 'Space 1', kind: category, hourlyRate: rate },
    ];
    services = [
      { name: isArabic ? 'خدمة مخصصة' : 'Standard Service Addon', price: 50 },
    ];
    amenities = ['AC', 'Wi-Fi', 'Parking'];
    description = isArabic ? 'مساحة راقية مجهزة بالكامل لتلبية كافة احتياجاتك.' : 'Fully equipped venue space.';
  }

  const address = isArabic ? `${city}، مصر` : `${city}, Egypt`;

  return {
    name,
    type,
    category,
    city,
    address,
    location: address,
    description,
    openHour: 10,
    closeHour: 24,
    depositPercent,
    instaPayAddress: instaPay,
    vodafoneCashNumber: phone,
    amenities,
    spaces,
    items: spaces,
    services,
  };
}

export function registerAiRoutes(app: Hono): void {
  app.post('/api/ai/venue-generator', async (c: any) => {
    let body: any = {};
    try {
      body = await c.req.json();
    } catch (_) {
      body = {};
    }

    const prompt = String(body.prompt || '').trim();
    const imageBase64 = String(body.imageBase64 || '').trim();
    const mimeType = String(body.mimeType || 'image/jpeg').trim();
    const categoryHint = String(body.categoryHint || '').trim();
    const isArabic = Boolean(body.isArabic || /[\u0600-\u06FF]/.test(prompt));

    const geminiApiKey = getEnv('GEMINI_API_KEY');

    // 1. If Gemini API Key is available, call Gemini 1.5 Flash
    if (geminiApiKey) {
      try {
        const systemInstruction = `You are Hagzy AI, an expert venue operations generator for the Egyptian booking market (sports, padel, football, salons, grooming, playstation, billiards, entertainment).
Given the user's text description or photo of a price sheet / board / flyer:
1. Extract or determine:
   - name: Venue business name.
   - type: Must be "sports", "salon", or "lounge".
   - category: e.g. "padel", "football", "salon", "playstation", "billiards".
   - city: Egyptian city (New Cairo, Maadi, Sheikh Zayed, Nasr City, Alexandria, Tanta, Mansoura, etc.).
   - address: Detailed area or street in Egypt.
   - description: 1-2 sentence compelling marketing description (in ${isArabic ? 'Arabic' : 'English'}).
   - openHour: Integer 0-23 (default 10).
   - closeHour: Integer 0-23 (default 24).
   - depositPercent: Integer 0-100 (default 25).
   - instaPayAddress: Extract if handle like name@instapay is mentioned, otherwise "".
   - vodafoneCashNumber: Extract Egyptian 010/011/012/015 11-digit mobile wallet if mentioned, otherwise "".
   - amenities: String array of key amenities (e.g. Parking, AC, Wi-Fi, Showers, Floodlights, Café).
   - spaces: Array of bookable units/spaces, each with: { "name": string, "kind": string, "hourlyRate": number (in EGP) }.
   - services: Array of add-on services or menu items with: { "name": string, "price": number (in EGP) }.
Output MUST be strict JSON matching this structure without Markdown backticks.`;

        const contents: any[] = [];
        const parts: any[] = [];

        if (imageBase64) {
          parts.push({
            inlineData: {
              mimeType: mimeType || 'image/jpeg',
              data: imageBase64.replace(/^data:[^;]+;base64,/, ''),
            },
          });
        }

        parts.push({
          text: `${prompt || 'Extract and create a complete Egyptian venue setup from this input.'} Category hint: ${categoryHint || 'auto'}.`,
        });

        contents.push({ parts });

        const candidateModels = ['gemini-3.5-flash-lite', 'gemini-flash-lite-latest'];
        let geminiData: any = null;

        for (const model of candidateModels) {
          try {
            const resp = await fetch(
              `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiApiKey}`,
              {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                signal: AbortSignal.timeout(7000),
                body: JSON.stringify({
                  contents,
                  systemInstruction: { parts: [{ text: systemInstruction }] },
                  generationConfig: {
                    responseMimeType: 'application/json',
                    temperature: 0.2,
                  },
                }),
              }
            );

            if (resp.ok) {
              geminiData = await resp.json();
              break;
            }
          } catch (_) {}
        }

        if (geminiData) {
          const rawText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
          if (rawText) {
            const parsed = JSON.parse(rawText);
            // Sanitize minimum deposit
            parsed.depositPercent = Math.max(0, Math.min(100, Number(parsed.depositPercent || 25)));
            parsed.spaces = Array.isArray(parsed.spaces) && parsed.spaces.length > 0
              ? parsed.spaces.map((s: any) => ({
                  name: String(s.name || 'Space 1').trim(),
                  kind: String(s.kind || parsed.category || 'Standard').trim(),
                  hourlyRate: Math.max(10, Number(s.hourlyRate || 200)),
                }))
              : [{ name: 'Space 1', kind: parsed.category || 'Standard', hourlyRate: 200 }];
            parsed.services = Array.isArray(parsed.services)
              ? parsed.services.map((sv: any) => ({
                  name: String(sv.name || 'Add-on').trim(),
                  price: Math.max(5, Number(sv.price || 50)),
                }))
              : [];
            parsed.amenities = Array.isArray(parsed.amenities) ? parsed.amenities.map(String) : [];
            parsed.items = parsed.spaces;

            return c.json({
              success: true,
              source: 'gemini-3.5-flash-lite',
              venue: parsed,
            });
          }
        }
      } catch (err: any) {
        console.warn('[AI_VENUE_GENERATOR] Gemini call failed, falling back to heuristic templates:', err?.message || err);
      }
    }

    // 2. High-accuracy fallback: heuristic Egyptian templates (works 100% offline or with zero API key)
    const fallbackVenue = buildFallbackVenueFromTemplate(prompt, categoryHint, isArabic);
    return c.json({
      success: true,
      source: 'egyptian-market-heuristics-fallback',
      venue: fallbackVenue,
    });
  });
}

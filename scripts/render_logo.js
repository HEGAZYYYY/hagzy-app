const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

function renderSvg(svgContent, outputPath, width, height) {
  const htmlPath = path.resolve(__dirname, 'temp_render.html');
  const html = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: ${width}px; height: ${height}px; background: transparent; overflow: hidden; }
  svg { width: ${width}px; height: ${height}px; display: block; }
</style>
</head>
<body>
${svgContent}
</body>
</html>`;

  fs.writeFileSync(htmlPath, html, 'utf8');
  
  const cmd = `"${chromePath}" --headless=new --screenshot="${outputPath}" --window-size=${width},${height} --default-background-color=00000000 "file://${htmlPath.replace(/\\/g, '/')}"`;
  execSync(cmd, { stdio: 'inherit' });
  
  if (fs.existsSync(htmlPath)) {
    fs.unlinkSync(htmlPath);
  }
}

const projectRoot = path.resolve(__dirname, '..');
const originalSvg = fs.readFileSync(path.join(projectRoot, 'assets/hagzy_logo.svg'), 'utf8');

// Also create square solid version (full bleed for avatars, social media & BIMI)
const squareSvg = originalSvg.replace('rx="64"', '');

// Targets
const outDir = path.join(projectRoot, 'assets');
const artifactDir = 'C:\\Users\\Mohamed Hegazy\\.gemini\\antigravity\\brain\\9952dac2-2bbe-435a-8ea4-9b3d165ef4b6';

console.log('Rendering 1024x1024 rounded logo...');
renderSvg(originalSvg, path.join(outDir, 'hagzy_logo_1024.png'), 1024, 1024);

console.log('Rendering 2048x2048 rounded logo...');
renderSvg(originalSvg, path.join(outDir, 'hagzy_logo_2048.png'), 2048, 2048);

console.log('Rendering 2048x2048 square logo (for avatars / profiles)...');
renderSvg(squareSvg, path.join(outDir, 'hagzy_logo_square_2048.png'), 2048, 2048);

// Copy to artifact directory so it can be viewed directly
fs.copyFileSync(path.join(outDir, 'hagzy_logo_2048.png'), path.join(artifactDir, 'hagzy_logo_2048.png'));
fs.copyFileSync(path.join(outDir, 'hagzy_logo_square_2048.png'), path.join(artifactDir, 'hagzy_logo_square_2048.png'));

console.log('Done rendering high quality logos!');

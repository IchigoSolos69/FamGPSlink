import { readFileSync, writeFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';

// Render the app's simple geometric house/map-pin mark, without a paid asset
// service or binary design dependency. Re-run when changing the brand colors.
function inside(x, y) {
  const circle = (cx, cy, radius) => (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2;
  const pin = circle(.5, .39, .24) || (y >= .39 && y <= .82 && Math.abs(x - .5) <= .24 * (.82 - y) / .43);
  const hole = circle(.5, .39, .15);
  const house = (y >= .29 && y <= .38 && Math.abs(x - .5) <= (y - .29) * 1.35) ||
    (x >= .42 && x <= .58 && y >= .37 && y <= .49);
  const door = x >= .48 && x <= .52 && y >= .43 && y <= .49;
  return (pin && !hole) || (house && !door);
}
function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  }
  return (value ^ 0xffffffff) >>> 0;
}
function chunk(kind, data) {
  const tag = Buffer.from(kind);
  const result = Buffer.alloc(data.length + 12);
  result.writeUInt32BE(data.length);
  tag.copy(result, 4); data.copy(result, 8);
  result.writeUInt32BE(crc32(Buffer.concat([tag, data])), data.length + 8);
  return result;
}
function png(size) {
  const bytes = Buffer.alloc(size * (size * 3 + 1));
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    let coverage = 0;
    for (const sy of [.25, .75]) for (const sx of [.25, .75]) coverage += inside((x + sx) / size, (y + sy) / size) ? .25 : 0;
    const offset = y * (size * 3 + 1) + 1 + x * 3;
    [22, 116, 91].forEach((color, component) => bytes[offset + component] = Math.round(color + (255 - color) * coverage));
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(size); header.writeUInt32BE(size, 4);
  header[8] = 8; header[9] = 2; // RGB, no transparency (required for iOS app icons).
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(bytes)), chunk('IEND', Buffer.alloc(0))]);
}
const assetRoot = new URL('../ios/Runner/Assets.xcassets/AppIcon.appiconset/', import.meta.url);
const assets = JSON.parse(readFileSync(new URL('Contents.json', assetRoot)));
for (const image of assets.images) if (image.filename) {
  const size = Math.round(Number(image.size.split('x')[0]) * Number(image.scale.replace('x', '')));
  writeFileSync(new URL(image.filename, assetRoot), png(size));
}
for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
  writeFileSync(new URL(`../android/app/src/main/res/mipmap-${density}/ic_launcher.png`, import.meta.url), png(size));
}
console.log('Generated FamGPSlink app icons for Android and iOS.');

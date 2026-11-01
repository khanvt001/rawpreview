import type {Lang} from './fonts';

// One idea per scene. Headlines ≤ 6 words, captions ≤ 10 words.
export const copy = {
  en: {
    tagline: 'Insert the card, see every RAW, copy only the keepers.',
    preview: {step: '1 / 4 · Preview', title: 'Every RAW, instantly.', caption: 'Straight from the SD card. No import, no catalog.',
      card: 'Card detected', cardLabel: 'Opens on its own', stat: '463 RAW · 467 JPEG', statLabel: 'Read straight off the card'},
    looks: {step: 'Film looks', title: '451 film looks.', caption: 'Hover to preview a look. Click to apply it.',
      cats: ['Geographic & cultural', 'Black & white film', 'Color negative film']},
    cull: {step: '2 / 4 · Cull', title: 'Mark the keepers.', caption: 'Rate with 1–5. Press S to mark for copy.'},
    share: {step: '3 / 4 · Share', title: 'Send to your phone.', caption: 'AirDrop the keepers as JPEGs, film look included.',
      sending: 'AirDrop · 3 JPEGs', sendingLabel: 'Tokyo Neon Night baked in, GPS removed', sent: 'Sent to iPhone', sentLabel: 'Ready to post before you get home'},
    copy: {step: '4 / 4 · Copy', title: 'Copy only those. Eject.', caption: 'One shortcut copies the marked files to your Mac.',
      stat: '3 copied · 78.9 MB in 1 sec', statLabel: 'Stars travel in .xmp sidecars', eject: 'Card ejected', ejectLabel: 'Safe to pull out'},
    outro: {title: 'RawPreview', caption: 'Free · macOS 14 Sonoma or later', cta: 'Download for macOS'},
  },
  vi: {
    tagline: 'Cắm thẻ, xem thẳng ảnh RAW, chỉ sao chép tấm ưng ý.',
    preview: {step: '1 / 4 · Xem', title: 'Xem ảnh RAW tức thì.', caption: 'Đọc thẳng từ thẻ SD. Không import, không catalog.',
      card: 'Đã nhận thẻ SD', cardLabel: 'Tự động mở ngay khi cắm', stat: '463 RAW · 467 JPEG', statLabel: 'Hiển thị trực tiếp từ thẻ nhớ'},
    looks: {step: 'Presets màu phim', title: '451 preset màu phim.', caption: 'Lướt chuột để xem thử, nhấp để áp màu.',
      cats: ['Địa lý & Văn hoá', 'Phim đen trắng', 'Phim âm bản màu']},
    cull: {step: '2 / 4 · Lọc ảnh', title: 'Đánh dấu tấm ưng ý.', caption: 'Phím 1–5 để chấm sao. Phím S để đánh dấu sao chép.'},
    share: {step: '3 / 4 · Chia sẻ', title: 'Gửi nhanh qua điện thoại.', caption: 'Gửi ảnh JPEG kèm màu phim qua AirDrop tức thì.',
      sending: 'AirDrop · 3 JPEG', sendingLabel: 'Áp màu Tokyo Neon Night · Tự ẩn GPS', sent: 'Đã gửi sang iPhone', sentLabel: 'Có ảnh đăng ngay tại buổi chụp'},
    copy: {step: '4 / 4 · Sao chép', title: 'Sao chép đúng tấm đã chọn.', caption: 'Nhấn ⌘↩ để sao chép ảnh đã đánh dấu về máy Mac.',
      stat: 'Đã chép 3 ảnh · 78,9 MB (1 giây)', statLabel: 'Giữ nguyên số sao qua tệp .xmp đi kèm', eject: 'Đã tháo thẻ', ejectLabel: 'Có thể rút thẻ an toàn'},
    outro: {title: 'RawPreview', caption: 'Miễn phí · macOS 14 Sonoma trở lên', cta: 'Tải về cho macOS'},
  },
} satisfies Record<Lang, unknown>;

export type Copy = (typeof copy)['en'];

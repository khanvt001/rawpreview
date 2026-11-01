// Every line on the page, in English and Vietnamese. Names from the app
// (menu items, presets, shortcuts) stay as the app shows them.

export type Lang = 'en' | 'vi';

// Built-in categories as the app lists them, with their preset counts
// (rawpreview/Resources/BuiltInPresets.json).
const categoryCounts = [83, 58, 20, 52, 25, 40, 33, 20, 25, 32, 23, 20, 20];

const en = {
  meta: {
    title: 'RawPreview — Cull before you copy',
    description:
      'A free macOS app for photographers: insert an SD card, see every RAW instantly, try 451 film looks, mark the keepers, copy only those, eject.',
  },
  nav: {how: 'How it works', looks: 'Film looks', formats: 'Formats', faq: 'FAQ', download: 'Download'},
  theme: {toDark: 'Switch to Darkroom (dark)', toLight: 'Switch to Daylight (light)'},
  langSwitch: {label: 'Tiếng Việt', short: 'VI'},
  hero: {
    eyebrow: 'Free for macOS',
    title: 'Cull before you copy.',
    body: 'Insert the card and every RAW opens instantly. Try film looks, mark the keepers, copy only those, eject. No import, no catalog.',
    cta: 'Download for macOS',
    note: 'Free · macOS 14 Sonoma or later',
    secondary: 'See how it works',
    videoLabel: 'RawPreview product tour, 48 seconds',
    play: 'Play with sound',
  },
  how: {
    eyebrow: 'How it works',
    title: 'Four steps between the card and your Mac.',
    steps: [
      {
        id: 'preview',
        step: '1 / 4 · Preview',
        title: 'Every RAW, instantly.',
        body: 'Insert the card and RawPreview opens on its own. The grid fills straight from the SD card, EXIF under every thumbnail. Nothing is imported, nothing is copied yet.',
        readout: '463 RAW · 467 JPEG',
        readoutLabel: 'Read straight off the card',
        alt: 'RawPreview showing a NIKON Z 50 card as a grid of NEF thumbnails with aperture, shutter speed and ISO under each.',
      },
      {
        id: 'cull',
        step: '2 / 4 · Cull',
        title: 'Mark the keepers.',
        body: 'Rate with 1–5 and press S to mark a photo for copy. Stars go into .xmp sidecars, which Lightroom Classic and Capture One read.',
        keys: ['1–5', 'S'],
        keysLabel: 'Rate · Mark for Copy',
        alt: 'The grid with three photos marked for copy and star ratings under them; the status bar reads 3 marked, 78.9 MB.',
      },
      {
        id: 'share',
        step: '3 / 4 · Share',
        title: 'Send to your phone.',
        body: 'AirDrop the keepers as JPEGs with the film look baked in and GPS removed. Ready to post before you get home.',
        readout: 'AirDrop · 3 JPEGs',
        readoutLabel: 'Tokyo Neon Night baked in, GPS removed',
        alt: 'The AirDrop sheet over the grid, showing the photos sent to an iPhone.',
      },
      {
        id: 'copy',
        step: '4 / 4 · Copy',
        title: 'Copy only those. Eject.',
        body: 'One shortcut copies the marked files to your Mac. Then eject the card from the sidebar.',
        keys: ['⌘↩'],
        keysLabel: 'Copy Marked Files',
        readout: '3 copied · 78.9 MB in 1 sec',
        alt: 'The Copy Complete sheet: 3 copied, 78.9 MB in 1 sec, with Show in Finder, Clear Marks and Done.',
      },
    ],
  },
  looks: {
    eyebrow: 'Film looks',
    title: '451 film looks.',
    body: 'Hover a look to preview it on the photo, click to apply it. Press \\ to compare with the original. Your own Lightroom presets (.lrtemplate or .xmp) import too.',
    original: 'Original',
    compare: 'Compare the original with the film look',
    choose: 'Choose a look',
    exif: 'DSC_6773.NEF · ƒ/6.3 · 1/100 s · ISO 200',
    shotNote: 'Rendered by RawPreview from the NEF on the card.',
    categoriesTitle: '13 categories',
    categories: [
      'Color Negative Film',
      'Black & White Film',
      'Slide / E-6 Film',
      'Creative / Cinematic',
      'Alternative Processes',
      'Utility & Tools',
      'Genre-Specific',
      'Seasonal & Holiday',
      'Historical Decade',
      'Geographic & Cultural',
      'Mobile & Social Media',
      'Photographer Styles',
      'Video LUT Reference',
    ],
    credit: 'Built-in looks from Emulsion Presets by peva3, MIT License.',
  },
  formats: {
    eyebrow: 'Formats',
    title: 'Every card, every camera.',
    body: '19 RAW formats, plus JPEG, HEIF and video side by side on the same grid.',
    rawLabel: 'RAW',
    otherLabel: 'Also',
    other: ['JPEG', 'HEIF', 'Video'],
  },
  faq: {
    eyebrow: 'FAQ',
    title: 'Before you insert the card.',
    items: [
      {q: 'Does it import or move my photos?', a: 'No. Whether it is a card or a folder picked with Open Folder…, RawPreview reads the files where they are. Nothing is copied until you choose Copy Marked Files.'},
      {q: 'Will Lightroom see my ratings?', a: 'Yes. Stars are saved in .xmp sidecars next to each RAW, which Lightroom Classic and Capture One read.'},
      {q: 'Can I use my own presets?', a: 'Yes. Import Lightroom develop presets (.lrtemplate or .xmp), or whole folders of them, and they sit beside the 451 built-in looks.'},
      {q: 'Can it delete rejects from the card?', a: 'Only if you turn on Delete on memory cards in Settings, and it asks before deleting anything.'},
      {q: 'What do I need?', a: 'A Mac with macOS 14 Sonoma or later. RawPreview is free.'},
    ],
  },
  final: {
    title: 'Insert the card. Mark the keepers. Copy only those.',
  },
  footer: {
    tagline: 'A free macOS app for photographers.',
    music: 'Music in the video: “Fun is Fun” by Aylex (freetouse.com).',
  },
};

type Copy = typeof en;

const vi: Copy = {
  meta: {
    title: 'RawPreview — Lọc ảnh trước khi sao chép',
    description:
      'Ứng dụng macOS miễn phí cho người chụp ảnh: cắm thẻ SD, xem ngay mọi ảnh RAW, thử 451 preset màu phim, đánh dấu tấm ưng ý, chỉ sao chép những tấm đó rồi tháo thẻ.',
  },
  nav: {how: 'Cách dùng', looks: 'Màu phim', formats: 'Định dạng', faq: 'Hỏi đáp', download: 'Tải về'},
  theme: {toDark: 'Chuyển sang Darkroom (tối)', toLight: 'Chuyển sang Daylight (sáng)'},
  langSwitch: {label: 'English', short: 'EN'},
  hero: {
    eyebrow: 'Miễn phí cho macOS',
    title: 'Lọc trước, chép sau.',
    body: 'Cắm thẻ là xem ngay mọi ảnh RAW. Thử màu phim, đánh dấu tấm ưng ý, chỉ sao chép những tấm đó rồi tháo thẻ. Không import, không catalog.',
    cta: 'Tải về cho macOS',
    note: 'Miễn phí · macOS 14 Sonoma trở lên',
    secondary: 'Xem cách dùng',
    videoLabel: 'Video giới thiệu RawPreview, 48 giây',
    play: 'Phát kèm âm thanh',
  },
  how: {
    eyebrow: 'Cách dùng',
    title: 'Bốn bước từ thẻ nhớ về máy Mac.',
    steps: [
      {
        id: 'preview',
        step: '1 / 4 · Xem',
        title: 'Xem ảnh RAW tức thì.',
        body: 'Cắm thẻ là RawPreview tự mở. Lưới ảnh hiện thẳng từ thẻ SD, thông số EXIF nằm dưới từng ảnh. Chưa có gì bị import hay sao chép.',
        readout: '463 RAW · 467 JPEG',
        readoutLabel: 'Hiển thị trực tiếp từ thẻ nhớ',
        alt: 'RawPreview hiển thị thẻ NIKON Z 50 dưới dạng lưới ảnh NEF, khẩu độ, tốc độ và ISO nằm dưới từng ảnh.',
      },
      {
        id: 'cull',
        step: '2 / 4 · Lọc ảnh',
        title: 'Đánh dấu tấm ưng ý.',
        body: 'Phím 1–5 để chấm sao, phím S để đánh dấu sao chép. Số sao được lưu vào tệp .xmp đi kèm, Lightroom Classic và Capture One đều đọc được.',
        keys: ['1–5', 'S'],
        keysLabel: 'Chấm sao · Đánh dấu sao chép',
        alt: 'Lưới ảnh với ba tấm đã đánh dấu sao chép và số sao bên dưới; thanh trạng thái ghi 3 marked, 78,9 MB.',
      },
      {
        id: 'share',
        step: '3 / 4 · Chia sẻ',
        title: 'Gửi nhanh qua điện thoại.',
        body: 'Gửi tấm ưng ý qua AirDrop dưới dạng JPEG, đã áp màu phim và tự ẩn GPS. Có ảnh đăng ngay tại buổi chụp.',
        readout: 'AirDrop · 3 JPEG',
        readoutLabel: 'Áp màu Tokyo Neon Night · Tự ẩn GPS',
        alt: 'Bảng AirDrop phía trên lưới ảnh, ảnh đã được gửi sang iPhone.',
      },
      {
        id: 'copy',
        step: '4 / 4 · Sao chép',
        title: 'Chép đúng tấm đã chọn. Tháo thẻ.',
        body: 'Một phím tắt sao chép các tấm đã đánh dấu về máy Mac. Xong thì tháo thẻ ngay ở thanh bên.',
        keys: ['⌘↩'],
        keysLabel: 'Copy Marked Files',
        readout: 'Đã chép 3 ảnh · 78,9 MB (1 giây)',
        alt: 'Bảng Copy Complete: 3 copied, 78,9 MB in 1 sec, cùng các nút Show in Finder, Clear Marks và Done.',
      },
    ],
  },
  looks: {
    eyebrow: 'Màu phim',
    title: '451 preset màu phim.',
    body: 'Lướt chuột qua một preset để xem thử trên ảnh, nhấp để áp màu. Nhấn \\ để so với ảnh gốc. Nhập được cả preset Lightroom của bạn (.lrtemplate hoặc .xmp).',
    original: 'Ảnh gốc',
    compare: 'So sánh ảnh gốc với màu phim',
    choose: 'Chọn màu phim',
    exif: 'DSC_6773.NEF · ƒ/6.3 · 1/100 s · ISO 200',
    shotNote: 'RawPreview dựng trực tiếp từ tệp NEF trên thẻ.',
    categoriesTitle: '13 nhóm',
    categories: [
      'Phim âm bản màu',
      'Phim đen trắng',
      'Phim dương bản / E-6',
      'Sáng tạo / Điện ảnh',
      'Kỹ thuật in cổ',
      'Tiện ích',
      'Theo thể loại',
      'Mùa & Lễ hội',
      'Theo thập niên',
      'Địa lý & Văn hoá',
      'Mạng xã hội',
      'Phong cách nhiếp ảnh gia',
      'LUT video',
    ],
    credit: 'Preset có sẵn lấy từ Emulsion Presets của peva3, giấy phép MIT.',
  },
  formats: {
    eyebrow: 'Định dạng',
    title: 'Thẻ nào, máy nào cũng đọc.',
    body: '19 định dạng RAW, cùng JPEG, HEIF và video nằm chung một lưới.',
    rawLabel: 'RAW',
    otherLabel: 'Cùng với',
    other: ['JPEG', 'HEIF', 'Video'],
  },
  faq: {
    eyebrow: 'Hỏi đáp',
    title: 'Trước khi cắm thẻ.',
    items: [
      {q: 'Ứng dụng có import hay di chuyển ảnh của tôi không?', a: 'Không. Dù là thẻ nhớ hay thư mục mở bằng Open Folder…, RawPreview đọc ảnh ngay tại chỗ. Chưa có gì được sao chép cho tới khi bạn chọn Copy Marked Files.'},
      {q: 'Lightroom có thấy số sao tôi chấm không?', a: 'Có. Số sao được lưu trong tệp .xmp nằm cạnh mỗi ảnh RAW, Lightroom Classic và Capture One đều đọc được.'},
      {q: 'Tôi dùng preset riêng được không?', a: 'Được. Nhập preset develop của Lightroom (.lrtemplate hoặc .xmp), hoặc cả thư mục preset, chúng sẽ nằm cạnh 451 preset có sẵn.'},
      {q: 'Ứng dụng có xoá ảnh hỏng trên thẻ được không?', a: 'Chỉ khi bạn bật Delete on memory cards trong Settings, và ứng dụng luôn hỏi lại trước khi xoá.'},
      {q: 'Máy tôi cần gì?', a: 'Một máy Mac chạy macOS 14 Sonoma trở lên. RawPreview miễn phí.'},
    ],
  },
  final: {
    title: 'Cắm thẻ. Chọn tấm ưng\u00a0ý. Chỉ chép những tấm đó.',
  },
  footer: {
    tagline: 'Ứng dụng macOS miễn phí cho người chụp ảnh.',
    music: 'Nhạc trong video: “Fun is Fun” của Aylex (freetouse.com).',
  },
};

export const copy: Record<Lang, Copy> = {en, vi};
export {categoryCounts};

// RAW extensions the app reads, by maker (rawpreview/Models/MediaKind.swift).
export const rawFormats: {maker: string; ext: string[]}[] = [
  {maker: 'Nikon', ext: ['NEF', 'NRW']},
  {maker: 'Canon', ext: ['CR2', 'CR3', 'CRW']},
  {maker: 'Sony', ext: ['ARW', 'SRF', 'SR2']},
  {maker: 'Fujifilm', ext: ['RAF']},
  {maker: 'OM System / Olympus', ext: ['ORF']},
  {maker: 'Panasonic', ext: ['RW2']},
  {maker: 'Pentax', ext: ['PEF']},
  {maker: 'Samsung', ext: ['SRW']},
  {maker: 'Hasselblad', ext: ['3FR', 'FFF']},
  {maker: 'Phase One', ext: ['IIQ']},
  {maker: 'Leica', ext: ['RWL']},
  {maker: 'Sigma', ext: ['X3F']},
  {maker: 'Adobe / Leica / phones', ext: ['DNG']},
];

require "fileutils"

# Satu teks promosi (+ gambar opsional) milik sebuah TelegramTarget. Promo aktif dikirim bergantian (rotasi) sesuai
# jadwal promosi target, terpisah dari jadwal video. Gambar disimpan sebagai berkas JPEG di storage/telegram_promos.
class TelegramPromo < ApplicationRecord
  class ImageError < StandardError; end

  IMAGE_DIR = Rails.root.join("storage", "telegram_promos")
  MAX_PER_TARGET = 20
  MAX_TEXT = 4000      # batas pesan teks Telegram 4096
  MAX_CAPTION = 1024   # batas caption bila ada gambar
  MAX_UPLOAD = 8.megabytes
  MAX_PIXELS = 40_000_000
  IMAGE_LOADERS = %w[jpegload pngload webpload gifload].freeze

  belongs_to :telegram_target

  validates :body, presence: true
  validate :body_length
  validate :quota, on: :create

  after_destroy :remove_image_file
  after_save :sync_target
  after_destroy :sync_target

  scope :active, -> { where(enabled: true) }

  def image_path = IMAGE_DIR.join("#{id}.jpg")
  def image_exists? = has_image? && File.exist?(image_path)

  # Validasi + konversi unggahan ke JPEG (maks 1280px, metadata dibuang). Mengembalikan path berkas sementara.
  def self.process_image(uploaded)
    require "image_processing/vips"
    raise ImageError, I18n.t("admin.telegram.promo.image_missing") unless uploaded.respond_to?(:tempfile)
    raise ImageError, I18n.t("admin.telegram.promo.image_too_big", mb: MAX_UPLOAD / 1.megabyte) if uploaded.size > MAX_UPLOAD
    src = uploaded.tempfile.path
    img = Vips::Image.new_from_file(src)
    loader = img.get("vips-loader").to_s
    raise ImageError, I18n.t("admin.telegram.promo.image_type") unless IMAGE_LOADERS.any? { |l| loader.start_with?(l) }
    raise ImageError, I18n.t("admin.telegram.promo.image_pixels") if img.width * img.height > MAX_PIXELS
    ImageProcessing::Vips.source(src).loader(page: 0).resize_to_limit(1280, 1280).convert("jpg").saver(quality: 85, strip: true).call.path
  rescue Vips::Error
    raise ImageError, I18n.t("admin.telegram.promo.image_type")
  end

  def write_image!(processed_path)
    FileUtils.mkdir_p(IMAGE_DIR)
    FileUtils.cp(processed_path, image_path)
  end

  def remove_image_file = FileUtils.rm_f(image_path)

  private
  def body_length
    max = has_image? ? MAX_CAPTION : MAX_TEXT
    errors.add(:body, I18n.t("admin.telegram.promo.too_long", max: max, n: body.to_s.length)) if body.to_s.length > max
  end

  def quota
    errors.add(:base, I18n.t("admin.telegram.promo.quota", max: MAX_PER_TARGET)) if telegram_target && telegram_target.promos.count >= MAX_PER_TARGET
  end

  # Promosi target dimatikan otomatis bila tidak ada lagi promo aktif.
  def sync_target
    t = TelegramTarget.find_by(id: telegram_target_id) or return
    t.update_columns(promo_enabled: false, promo_next_run_at: nil, updated_at: Time.current) if t.promo_enabled? && !t.promos.active.exists?
  end
end

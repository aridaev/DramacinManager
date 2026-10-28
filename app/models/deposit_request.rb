# Pengajuan deposit "tanpa iklan". Bukti transfer disimpan di public/uploads/proofs/<instance_id>/ dan
# DIHAPUS saat disetujui/ditolak agar tidak memakan ruang disk.
class DepositRequest < ApplicationRecord
  belongs_to :instance
  belongs_to :member

  enum :status, { pending: 0, approved: 1, rejected: 2 }

  PROOF_DIR  = Rails.root.join("public/uploads/proofs")
  PROOF_MAX  = 5.megabytes
  PROOF_TYPES = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.freeze

  validates :days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 3650 }, allow_nil: true
  validates :note, length: { maximum: 200 }, allow_blank: true
  validate  :only_one_pending, on: :create

  scope :ordered, -> { order(Arel.sql("CASE status WHEN 0 THEN 0 ELSE 1 END"), created_at: :desc) }

  after_destroy :delete_proof_file
  before_save { self.amount_value = amount.to_s.gsub(/\D/, "").presence&.to_i }

  def proof_url = proof_path.present? ? "/uploads/proofs/#{proof_path}" : nil
  def proof_file = proof_path.present? ? PROOF_DIR.join(proof_path) : nil

  # Simpan bukti dari ActionDispatch::Http::UploadedFile; validasi tipe lewat magic bytes, bukan hanya content-type.
  def attach_proof(upload)
    return errors.add(:base, I18n.t("members.proof_required")) if upload.blank?
    return errors.add(:base, I18n.t("members.proof_too_big")) if upload.size > PROOF_MAX
    ext = sniff_ext(upload)
    return errors.add(:base, I18n.t("members.proof_bad_type")) unless ext
    dir = PROOF_DIR.join(instance_id.to_s); FileUtils.mkdir_p(dir)
    name = "#{SecureRandom.hex(12)}.#{ext}"
    File.open(dir.join(name), "wb") { |f| f.write(upload.read) }
    self.proof_path = "#{instance_id}/#{name}"; self.proof_type = ext; self.proof_size = upload.size
  end

  def approve!(grant_days = nil)
    d = (grant_days.presence || days.presence || instance.adfree_days).to_i.clamp(1, 3650)
    transaction do
      member.grant_adfree!(d)
      update!(status: :approved, days: d, reviewed_at: Time.current, adfree_until: member.adfree_until)
    end
    delete_proof_file
  end

  def reject!
    update!(status: :rejected, reviewed_at: Time.current)
    delete_proof_file
  end

  def delete_proof_file
    f = proof_file
    File.delete(f) if f && File.exist?(f)
    update_columns(proof_path: nil) if persisted? && proof_path.present?
  rescue SystemCallError => e
    Rails.logger.warn("[DepositRequest] gagal hapus bukti #{proof_path}: #{e.message}")
  end

  private
  def only_one_pending
    errors.add(:base, I18n.t("members.already_pending")) if member && member.deposit_requests.pending.exists?
  end

  def sniff_ext(upload)
    head = upload.read(12).to_s.b; upload.rewind
    return "jpg"  if head.start_with?("\xFF\xD8\xFF".b)
    return "png"  if head.start_with?("\x89PNG\r\n\x1A\n".b)
    return "webp" if head[0, 4] == "RIFF" && head[8, 4] == "WEBP"
    nil
  end
end

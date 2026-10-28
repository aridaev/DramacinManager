# Akun penonton per instance (terpisah dari User dashboard). Hanya dipakai untuk fitur bebas iklan:
# login username+password → unggah bukti deposit → pemilik instance approve → iklan hilang sampai adfree_until.
class Member < ApplicationRecord
  has_secure_password
  belongs_to :instance
  has_many :deposit_requests, dependent: :destroy

  USERNAME_RE = /\A[a-z0-9_.]{3,30}\z/

  before_validation { self.username = username.to_s.strip.downcase }
  validates :username, presence: true, format: { with: USERNAME_RE }, uniqueness: { scope: :instance_id }
  validates :password, length: { minimum: 4, maximum: 72 }, allow_nil: true

  scope :ordered, -> { order(created_at: :desc) }

  def adfree? = adfree_until.present? && adfree_until > Time.current
  def adfree_days_left = adfree? ? ((adfree_until - Time.current) / 1.day).ceil : 0

  # "3 hari 4 jam" / "4 jam 10 menit" / "10 menit"
  def adfree_left_text
    return "" unless adfree?
    d, r = (adfree_until - Time.current).to_i.divmod(86_400); h, r = r.divmod(3_600); m = r / 60
    if d > 0 then I18n.t("template.v1.members.left_days", d: d, h: h)
    elsif h > 0 then I18n.t("template.v1.members.left_hours", h: h, m: m)
    else I18n.t("template.v1.members.left_minutes", m: m)
    end
  end

  def approved_count = deposit_requests.select(&:approved?).size
  def approved_total = deposit_requests.sum { |r| r.approved? ? r.amount_value.to_i : 0 }
  def pending_request = deposit_requests.pending.order(created_at: :desc).first

  # Dihitung dari waktu approve; bila masih aktif, diperpanjang dari sisa masa aktif agar tidak hangus.
  def grant_adfree!(days)
    base = adfree? ? adfree_until : Time.current
    update!(adfree_until: base + days.to_i.days)
  end

  def revoke_adfree! = update!(adfree_until: nil)
end

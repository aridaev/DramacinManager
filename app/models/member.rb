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
  def pending_request = deposit_requests.pending.order(created_at: :desc).first

  # Perpanjang dari sisa masa aktif (bukan dari hari ini) agar deposit berulang tidak hangus.
  def grant_adfree!(days)
    base = adfree? ? adfree_until : Time.current
    update!(adfree_until: base + days.to_i.days)
  end

  def revoke_adfree! = update!(adfree_until: nil)
end

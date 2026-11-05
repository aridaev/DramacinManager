# Sumber API eksternal (hub). Awalnya hanya DracinAPI; admin bisa menambah sumber lain dari
# /admin/api_sources. Provider yang terhubung ke sumber memakai api_key sumber kecuali punya key sendiri.
class ApiSource < ApplicationRecord
  AUTH_MODES = %w[header_x_token query_code query_key bearer none hmac_sha256].freeze

  encrypts :api_key

  has_many :providers, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :base_url, presence: true, format: { with: %r{\Ahttps?://}i }
  validates :auth_mode, inclusion: { in: AUTH_MODES }

  before_validation { self.slug = name.to_s.parameterize if slug.blank? }
  before_validation { self.base_url = base_url.to_s.strip.chomp("/") }
  after_save :ensure_single_default, if: :is_default?

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(is_default: :desc, name: :asc) }
  scope :hmac, -> { where(auth_mode: "hmac_sha256") }

  def self.default = find_by(is_default: true) || ordered.first

  # Header/params yang perlu ditambahkan untuk auth (dipakai Client dan Base adapter).
  def auth_headers
    case auth_mode
    when "header_x_token" then { "x-token" => api_key }
    when "bearer"         then { "Authorization" => "Bearer #{api_key}" }
    else {}
    end.compact_blank
  end

  def auth_params
    case auth_mode
    when "query_code" then { (auth_param.presence || "code").to_sym => api_key }
    when "query_key"  then { (auth_param.presence || "key").to_sym => api_key }
    else {}
    end.compact_blank
  end

  def hmac? = auth_mode == "hmac_sha256"

  # Kesehatan (diisi DracinApi::Health saat runtime + rake dracin:health): tidak sehat = token ditolak / kuota habis / host down.
  scope :unhealthy, -> { where("unhealthy_until > ?", Time.current) }
  def healthy? = unhealthy_until.nil? || unhealthy_until <= Time.current
  def quota_ratio = (quota_limit.to_i.positive? ? quota_used.to_f / quota_limit : nil)
  def key_expiring_soon? = key_expires_at.present? && key_expires_at < 3.days.from_now
  # Platform di hub berkuota harian: 1 cek status per hari sudah cukup dan tidak boros kuota.
  def quota_limited? = quota_limit.to_i.positive?

  # Vorta: X-Timestamp (ms) + X-Signature = hex HMAC-SHA256("METHOD:/path?query:timestamp", secret).
  def hmac_headers(method, request_uri)
    ts = (Time.now.to_f * 1000).to_i.to_s
    { "X-Timestamp" => ts, "X-Signature" => OpenSSL::HMAC.hexdigest("SHA256", api_key.to_s, "#{method.to_s.upcase}:#{request_uri}:#{ts}") }
  end

  def status_url = status_path.present? ? "#{base_url}#{status_path.start_with?('/') ? '' : '/'}#{status_path}" : nil
  def configured? = api_key.present? || auth_mode == "none"

  private
  def ensure_single_default
    ApiSource.where.not(id: id).update_all(is_default: false)
  end
end

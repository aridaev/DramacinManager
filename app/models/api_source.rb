# Sumber API eksternal (hub). Awalnya hanya DracinAPI; admin bisa menambah sumber lain dari
# /admin/api_sources. Provider yang terhubung ke sumber memakai api_key sumber kecuali punya key sendiri.
class ApiSource < ApplicationRecord
  AUTH_MODES = %w[header_x_token query_code query_key bearer none].freeze

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

  def status_url = status_path.present? ? "#{base_url}#{status_path.start_with?('/') ? '' : '/'}#{status_path}" : nil
  def configured? = api_key.present? || auth_mode == "none"

  private
  def ensure_single_default
    ApiSource.where.not(id: id).update_all(is_default: false)
  end
end

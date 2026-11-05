class Setting < ApplicationRecord
  DRACIN_API_BASE_URL = "dracin_api.base_url"
  DRACIN_API_KEY      = "dracin_api.api_key"
  CF_API_TOKEN     = "cloudflare.api_token"
  CF_ACCOUNT_ID    = "cloudflare.account_id"
  CF_AUTH_EMAIL    = "cloudflare.auth_email"
  CF_SSL_MODE      = "cloudflare.ssl_mode"
  CF_TOKEN_STATUS  = "cloudflare.token_status"
  TP_API_KEY       = "tokenplus.api_key"
  TP_MODEL         = "tokenplus.model"
  TP_STATUS        = "tokenplus.status"
  TP_AUTO_MODEL    = "tokenplus.auto_model"
  TELEGRAM_API_ID   = "telegram.api_id"
  TELEGRAM_API_HASH = "telegram.api_hash"
  TELEGRAM_STATUS   = "telegram.status"
  VPS_IP           = "site.vps_ip"
  USERS_CAN_CREATE = "site.users_can_create_instances"
  MAX_PER_USER     = "site.max_instances_per_user"

  encrypts :value

  validates :key, presence: true, uniqueness: true

  def self.get(key, default = nil)
    find_by(key: key)&.value.presence || default
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value.presence
    record.save!
    record
  end

  # Kompatibilitas: nilai lama kini tinggal di ApiSource default (admin/api_sources).
  def self.dracin_api_base_url = ApiSource.default&.base_url.presence || get(DRACIN_API_BASE_URL, DracinApi::Client::DEFAULT_BASE_URL)
  def self.cloudflare_api_token  = get(CF_API_TOKEN)
  def self.cloudflare_account_id = get(CF_ACCOUNT_ID)
  def self.cloudflare_auth_email = get(CF_AUTH_EMAIL)
  def self.cloudflare_ssl_mode   = get(CF_SSL_MODE, "flexible")
  def self.vps_ip                = get(VPS_IP)
  def self.tokenplus_api_key     = get(TP_API_KEY)
  def self.tokenplus_model       = get(TP_MODEL, TokenPlusClient::DEFAULT_MODEL)
  def self.tokenplus_auto_model? = get(TP_AUTO_MODEL, "1") == "1"
  def self.telegram_api_id       = get(TELEGRAM_API_ID)
  def self.telegram_api_hash     = get(TELEGRAM_API_HASH)
  def self.users_can_create_instances? = get(USERS_CAN_CREATE, "1") == "1"
  def self.max_instances_per_user = get(MAX_PER_USER, "3").to_i
  def self.dracin_api_key      = ApiSource.default&.api_key.presence || get(DRACIN_API_KEY)
end

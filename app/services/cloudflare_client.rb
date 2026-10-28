require "net/http"

# Klien Cloudflare API v4 untuk otomasi domain instance:
#   buat zone → ambil nameserver → set SSL Flexible → buat record A @ dan CNAME www ke IP VPS.
# Token (Setting "cloudflare.api_token") butuh izin: Zone:Read, Zone:Edit, DNS:Edit, Zone Settings:Edit.
class CloudflareClient
  BASE = "https://api.cloudflare.com/client/v4".freeze
  class Error < StandardError; end

  def self.from_settings
    new(token: Setting.cloudflare_api_token, account_id: Setting.cloudflare_account_id, email: Setting.cloudflare_auth_email)
  end

  attr_reader :account_id

  # email terisi → kredensial dianggap Global API Key (header X-Auth-Email/X-Auth-Key); kosong → API Token (Bearer).
  def initialize(token:, account_id: nil, email: nil)
    @token = token.to_s.strip
    @account_id = account_id.to_s.strip.presence
    @email = email.to_s.strip.presence
  end

  def configured? = @token.present?
  def global_key? = @email.present?

  # Verifikasi kredensial; mengembalikan { "status" => "active", ... }.
  def verify_token
    return request(:get, "/user/tokens/verify") unless global_key?
    user = request(:get, "/user")
    { "status" => "active", "id" => user["id"], "mode" => "global_key", "email" => user["email"] }
  end

  # Akun yang dapat diakses token (untuk mengisi account_id otomatis bila kosong).
  def accounts = request(:get, "/accounts", query: { per_page: 20 })

  def find_zone(name)
    Array(request(:get, "/zones", query: { name: name, per_page: 1 })).first
  end

  # Membuat zone (type full) atau mengembalikan zone yang sudah ada di akun ini.
  def create_zone(name)
    find_zone(name) || begin
      body = { name: name, type: "full", jump_start: false }
      body[:account] = { id: account_id } if account_id
      request(:post, "/zones", body: body)
    end
  end

  def zone(zone_id) = request(:get, "/zones/#{zone_id}")

  def set_ssl_mode(zone_id, mode = "flexible")
    request(:patch, "/zones/#{zone_id}/settings/ssl", body: { value: mode })
  end

  def set_always_https(zone_id, on: true)
    request(:patch, "/zones/#{zone_id}/settings/always_use_https", body: { value: on ? "on" : "off" })
  rescue Error
    nil # setting ini tidak tersedia di semua plan; abaikan
  end

  def dns_records(zone_id, type: nil, name: nil)
    Array(request(:get, "/zones/#{zone_id}/dns_records", query: { type: type, name: name, per_page: 100 }.compact))
  end

  # Upsert record: kalau ada record dengan type+name yang sama, update; kalau tidak, buat.
  def upsert_dns(zone_id, type:, name:, content:, proxied: true, ttl: 1)
    existing = dns_records(zone_id, type: type, name: name).first
    payload = { type: type, name: name, content: content, proxied: proxied, ttl: ttl }
    if existing
      request(:put, "/zones/#{zone_id}/dns_records/#{existing['id']}", body: payload)
    else
      request(:post, "/zones/#{zone_id}/dns_records", body: payload)
    end
  end

  def delete_zone(zone_id) = request(:delete, "/zones/#{zone_id}")

  private
  def request(method, path, query: nil, body: nil)
    raise Error, "Token Cloudflare belum diisi" unless configured?
    uri = URI("#{BASE}#{path}")
    uri.query = URI.encode_www_form(query.compact) if query.present?
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
    req = klass.new(uri)
    if global_key?
      req["X-Auth-Email"] = @email
      req["X-Auth-Key"] = @token
    else
      req["Authorization"] = "Bearer #{@token}"
    end
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 6, read_timeout: 25) { |h| h.request(req) }
    json = JSON.parse(res.body.to_s) rescue { "success" => false, "errors" => [ { "message" => "Respons bukan JSON (HTTP #{res.code})" } ] }
    unless json["success"]
      msgs = Array(json["errors"]).map { |e| [ e["code"], e["message"] ].compact.join(": ") }.join("; ")
      raise Error, msgs.presence || "HTTP #{res.code}"
    end
    json["result"]
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise Error, "Cloudflare timeout"
  rescue SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
    raise Error, "Koneksi Cloudflare gagal: #{e.class}"
  end
end

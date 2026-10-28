require "net/http"

# Klien TokenPlus (https://tokenplus.net) — API kompatibel OpenAI: POST /v1/chat/completions, GET /v1/models.
class TokenPlusClient
  class Error < StandardError; end

  BASE_URL = "https://tokenplus.net".freeze
  DEFAULT_MODEL = "claude-sonnet-4-5".freeze
  # Pilihan cepat di admin; model lain bisa diketik manual (lihat daftar dari tombol "Tes & muat model").
  SUGGESTED_MODELS = %w[claude-opus-4-5 claude-opus-4-1 claude-sonnet-4-5 claude-sonnet-4 gpt-5 gpt-4.1 gemini-2.5-pro deepseek-v4-flash].freeze

  # Pilih Claude terbaik dari daftar model: Opus versi tertinggi, lalu Sonnet tertinggi (abaikan varian "thinking"/tanggal lama bila ada yang polos).
  def self.best_claude(models)
    pick = lambda do |family|
      cands = models.grep(/\Aclaude[-_.]?#{family}/i).reject { |m| m.match?(/thinking|preview|legacy/i) }
      cands.max_by { |m| v = m.scan(/\d+(?:\.\d+)?/).map(&:to_f); [ v[0] || 0, v[1] || 0, m.match?(/\d{8}/) ? 0 : 1 ] }
    end
    pick.call("opus") || pick.call("sonnet")
  end
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 170

  def self.from_settings = new(Setting.tokenplus_api_key, model: Setting.tokenplus_model)

  def initialize(api_key, model: DEFAULT_MODEL, base_url: BASE_URL)
    @api_key = api_key.to_s.strip
    @model = model.presence || DEFAULT_MODEL
    @base_url = base_url
  end

  attr_reader :model

  def configured? = @api_key.present?

  def models
    data = request(:get, "/v1/models")
    Array(data["data"]).filter_map { |m| m["id"] }.sort
  end

  # Mengembalikan teks balasan asisten.
  def chat(messages, temperature: 0.7, max_tokens: 4096, json: false)
    body = { model: @model, messages: messages, temperature: temperature, max_tokens: max_tokens }
    body[:response_format] = { type: "json_object" } if json
    data = request(:post, "/v1/chat/completions", body)
    content = data.dig("choices", 0, "message", "content")
    raise Error, I18n.t("tokenplus.empty_reply") if content.blank?
    content
  end

  private
  def request(method, path, body = nil)
    raise Error, I18n.t("tokenplus.not_configured") unless configured?
    uri = URI.parse(@base_url + path)
    req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@api_key}"
    req["Content-Type"] = "application/json"
    req["Accept"] = "application/json"
    req.body = body.to_json if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |h| h.request(req) }
    data = JSON.parse(res.body.to_s) rescue {}
    unless res.is_a?(Net::HTTPSuccess)
      msg = data.dig("error", "message") || data["message"] || res.body.to_s.truncate(200)
      raise Error, "HTTP #{res.code}: #{msg}"
    end
    data
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise Error, I18n.t("tokenplus.timeout")
  rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
    raise Error, "#{I18n.t('tokenplus.connection')} (#{e.class})"
  end
end

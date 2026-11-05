require "net/http"
require "json"
require "securerandom"

# Klien HTTP ke sidecar Telethon (127.0.0.1). api_id/api_hash dari Setting; secret dari ENV.
class TelegramClient
  class Error < StandardError; end
  class AuthError < Error; end
  class FloodWait < Error
    attr_reader :seconds
    def initialize(msg, seconds) = (super(msg); @seconds = seconds.to_i)
  end
  class Forbidden < Error; end

  def self.from_settings = new(api_id: Setting.telegram_api_id, api_hash: Setting.telegram_api_hash)

  def initialize(api_id:, api_hash:, url: ENV["TELEGRAM_SIDECAR_URL"].presence || "http://127.0.0.1:8765", secret: ENV["TELEGRAM_SIDECAR_SECRET"])
    @api_id, @api_hash, @url, @secret = api_id.to_s, api_hash.to_s, url, secret.to_s
  end

  def configured? = @api_id.present? && @api_hash.present? && @secret.present?

  def health = get("/health")
  def qr_start = post("/qr/start", creds)
  def qr_status(login_id) = get("/qr/status?login_id=#{CGI.escape(login_id)}")
  def qr_password(login_id, password) = post("/qr/password", { login_id: login_id, password: password })
  def qr_cancel(login_id) = post("/qr/cancel", { login_id: login_id })
  def me(session) = post("/me", creds(session))
  def dialogs(session) = post("/dialogs", creds(session))
  def logout(session) = post("/logout", creds(session))

  # Unggah video ke satu tujuan. peer = { peer_kind, peer_id, access_hash, username }.
  def send_video(session, peer:, video:, cover:, caption:, width:, height:, duration_ms:)
    meta = creds(session).merge(peer: peer, caption: caption, width: width, height: height, duration: (duration_ms.to_f / 1000).round)
    parts = [ [ "video", "video.mp4", "video/mp4", File.binread(video) ] ]
    parts << [ "cover", "cover.jpg", "image/jpeg", File.binread(cover) ] if cover && File.exist?(cover)
    multipart("/send", meta, parts, timeout: 600)
  end

  # Kirim promosi: teks saja, atau gambar JPEG + caption (image = path berkas atau nil).
  def send_promo(session, peer:, text:, image: nil)
    meta = creds(session).merge(peer: peer, text: text)
    parts = image && File.exist?(image) ? [ [ "image", "image.jpg", "image/jpeg", File.binread(image) ] ] : []
    multipart("/promo", meta, parts, timeout: 120)
  end

  private
  def multipart(path, meta, files, timeout:)
    boundary = "----dm#{SecureRandom.hex(12)}"
    parts = [ [ "meta", nil, "application/json", meta.to_json ] ] + files
    body = parts.map { |name, file, type, data|
      disp = %(Content-Disposition: form-data; name="#{name}"#{%(; filename="#{file}") if file})
      "--#{boundary}\r\n#{disp}\r\nContent-Type: #{type}\r\n\r\n".b + data.to_s.b + "\r\n".b
    }.join.b + "--#{boundary}--\r\n".b
    request(Net::HTTP::Post, path, body: body, headers: { "Content-Type" => "multipart/form-data; boundary=#{boundary}" }, timeout: timeout)
  end

  def creds(session = nil) = { api_id: @api_id, api_hash: @api_hash }.merge(session ? { session: session } : {})
  def get(path) = request(Net::HTTP::Get, path)
  def post(path, data) = request(Net::HTTP::Post, path, body: data.to_json, headers: { "Content-Type" => "application/json" })

  def request(klass, path, body: nil, headers: {}, timeout: 60)
    raise Error, I18n.t("admin.telegram.not_configured") unless configured?
    uri = URI.join(@url, path)
    req = klass.new(uri)
    req["X-Secret"] = @secret
    headers.each { |k, v| req[k] = v }
    req.body = body if body
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: timeout) { |h| h.request(req) }
    data = JSON.parse(res.body.to_s) rescue { "ok" => false, "error" => "bad_response", "message" => res.body.to_s.first(200) }
    return data if data["ok"]
    msg = data["message"].presence || "HTTP #{res.code}"
    case data["error"]
    when "auth" then raise AuthError, msg
    when "flood_wait" then raise FloodWait.new(msg, data["seconds"])
    when "forbidden" then raise Forbidden, msg
    else raise Error, msg
    end
  rescue Errno::ECONNREFUSED, Net::OpenTimeout, SocketError
    raise Error, I18n.t("admin.telegram.sidecar_down")
  end
end

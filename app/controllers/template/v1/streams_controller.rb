require "net/http"

# Proxy HLS same-origin. Dipakai untuk dua kasus:
#   1. stream ber-cookie (Vigloo/CloudFront signed cookie) — browser tidak bisa mengirim cookie lintas-domain;
#   2. CDN tanpa header CORS atau yang menolak Referer/Origin situs lain (freereels, dramawave, vibeshort, shortmax,
#      flickreels) — hls.js butuh CORS, jadi playlist + segmen diambil server lalu diteruskan.
# Playlist ditulis ulang agar semua URI (segmen, sub-playlist, key) lewat proxy ini. Konteks (host yang boleh
# diakses + cookie) disimpan di cache; host hanya berasal dari URL stream asli dan isi playlist hulu (bukan open proxy).
class Template::V1::StreamsController < ActionController::Base
  include Template::V1::InstanceAware::RouteOverrides
  CONTEXT_TTL = 2.hours
  PLAYLIST_TYPES = %w[application/vnd.apple.mpegurl application/x-mpegurl audio/mpegurl audio/x-mpegurl].freeze
  USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36".freeze

  # sid deterministik per (host, cookie) supaya cache browser untuk segmen tetap berlaku antar kunjungan.
  def self.register(stream)
    hosts = ([ stream.url ] + Array(stream.sources).map { |s| s[:url] }).filter_map { |u| URI.parse(u.to_s).host rescue nil }.uniq
    sid = Digest::SHA1.hexdigest([ hosts.sort, stream.cookies.to_a.sort ].to_json)[0, 20]
    Rails.cache.write([ "tv1_stream", sid ], { hosts: hosts, cookies: stream.cookies }, expires_in: CONTEXT_TTL)
    sid
  end

  def show
    ctx = Rails.cache.read([ "tv1_stream", params[:sid] ]) or return head(:not_found)
    hosts = Array(ctx[:hosts] || ctx[:host])
    uri = URI.parse(params[:u].to_s) rescue nil
    return head(:forbidden) unless uri.is_a?(URI::HTTPS) && hosts.include?(uri.host)

    response = fetch(uri, ctx[:cookies])
    return head(response.code.to_i) unless response.is_a?(Net::HTTPSuccess)

    if playlist?(uri, response)
      body, new_hosts = rewrite_playlist(response.body, uri, params[:sid])
      extra = new_hosts - hosts
      Rails.cache.write([ "tv1_stream", params[:sid] ], ctx.merge(hosts: hosts + extra), expires_in: CONTEXT_TTL) if extra.any?
      expires_in 30.seconds, public: false
      render plain: body, content_type: "application/vnd.apple.mpegurl"
    else
      expires_in 1.hour, public: true
      headers["Content-Range"] = response["Content-Range"] if response["Content-Range"].present?
      headers["Accept-Ranges"] = "bytes"
      send_data response.body, type: response["Content-Type"].presence || "video/mp2t", disposition: "inline", status: response.code.to_i
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError
    head :bad_gateway
  end

  private
  # Tanpa Referer/Origin: beberapa CDN (flickreels) menolak bila ada Referer situs lain.
  def fetch(uri, cookies, redirects = 3)
    request = Net::HTTP::Get.new(uri)
    request["Cookie"] = cookies.map { |k, v| "#{k}=#{v}" }.join("; ") if cookies.present?
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "*/*"
    request["Range"] = request_range if request_range.present?
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 30) { |http| http.request(request) }
    if response.is_a?(Net::HTTPRedirection) && redirects.positive? && response["Location"].present?
      fetch(URI.join(uri, response["Location"]), cookies, redirects - 1)
    else
      response
    end
  end

  def request_range = request.headers["Range"].to_s

  def playlist?(uri, response)
    uri.path.end_with?(".m3u8") || uri.path.include?("/hls/") && response.body.to_s.lstrip.start_with?("#EXTM3U") ||
      PLAYLIST_TYPES.any? { |t| response["Content-Type"].to_s.downcase.start_with?(t) }
  end

  # Mengembalikan [playlist baru, host yang dirujuk] — host dari playlist hulu ikut diizinkan (CDN segmen sering beda host).
  def rewrite_playlist(body, base, sid)
    hosts = []
    out = body.each_line.map do |line|
      l = line.chomp
      if l.start_with?("#")
        l.gsub(/URI="([^"]+)"/) { u = URI.join(base, Regexp.last_match(1)); hosts << u.host; %(URI="#{proxy_url(sid, u)}") }
      elsif l.strip.empty?
        l
      else
        u = URI.join(base, l.strip); hosts << u.host
        proxy_url(sid, u)
      end
    end.join("\n")
    [ out, hosts.compact.uniq ]
  end

  def proxy_url(sid, uri)
    template_v1_stream_path(sid, u: uri.to_s)
  end
end

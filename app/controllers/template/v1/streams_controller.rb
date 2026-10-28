require "net/http"

# Proxy HLS untuk stream yang dilindungi signed cookie (mis. Vigloo/CloudFront): browser tidak bisa
# mengirim cookie lintas-domain, jadi playlist diambil di server, URI di dalamnya ditulis ulang ke
# proxy ini, dan segmen diteruskan dengan cookie yang sama. Konteks (host + cookie) disimpan di cache
# dengan id acak; URL yang diminta harus satu host dengan stream aslinya (bukan open proxy).
class Template::V1::StreamsController < ActionController::Base
  include Template::V1::InstanceAware::RouteOverrides
  CONTEXT_TTL = 2.hours
  PLAYLIST_TYPES = %w[application/vnd.apple.mpegurl application/x-mpegurl audio/mpegurl].freeze

  def self.register(stream)
    sid = SecureRandom.hex(10)
    host = URI.parse(stream.url).host
    Rails.cache.write([ "tv1_stream", sid ], { host: host, cookies: stream.cookies }, expires_in: CONTEXT_TTL)
    sid
  end

  def show
    ctx = Rails.cache.read([ "tv1_stream", params[:sid] ]) or return head(:not_found)
    uri = URI.parse(params[:u].to_s) rescue nil
    return head(:forbidden) unless uri.is_a?(URI::HTTPS) && uri.host == ctx[:host]

    response = fetch(uri, ctx[:cookies])
    return head(response.code.to_i) unless response.is_a?(Net::HTTPSuccess)

    if playlist?(uri, response)
      expires_in 30.seconds, public: false
      render plain: rewrite_playlist(response.body, uri, params[:sid]), content_type: "application/vnd.apple.mpegurl"
    else
      expires_in 1.hour, public: true
      send_data response.body, type: response["Content-Type"].presence || "application/octet-stream", disposition: "inline"
    end
  end

  private
  def fetch(uri, cookies, redirects = 2)
    request = Net::HTTP::Get.new(uri)
    request["Cookie"] = cookies.map { |k, v| "#{k}=#{v}" }.join("; ") if cookies.present?
    request["User-Agent"] = "DracinManager/1.0"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 30) { |http| http.request(request) }
    if response.is_a?(Net::HTTPRedirection) && redirects.positive? && response["Location"].present?
      fetch(URI.join(uri, response["Location"]), cookies, redirects - 1)
    else
      response
    end
  end

  def playlist?(uri, response)
    uri.path.end_with?(".m3u8") || PLAYLIST_TYPES.any? { |t| response["Content-Type"].to_s.downcase.start_with?(t) }
  end

  def rewrite_playlist(body, base, sid)
    body.each_line.map do |line|
      l = line.chomp
      if l.start_with?("#")
        l.gsub(/URI="([^"]+)"/) { %(URI="#{proxy_url(sid, URI.join(base, Regexp.last_match(1)))}") }
      elsif l.strip.empty?
        l
      else
        proxy_url(sid, URI.join(base, l.strip))
      end
    end.join("\n")
  end

  def proxy_url(sid, uri)
    template_v1_stream_path(sid, u: uri.to_s)
  end
end

# Satu baris = satu tampilan halaman di situs publik instance. Dicatat async (VisitTrackJob) dari
# Template::V1::BaseController; data pribadi dibatasi: IP hanya prefix /24, pengunjung unik = hash harian.
class Visit < ApplicationRecord
  belongs_to :instance

  RETENTION = 90.days
  KINDS = %w[home drama watch search genre member other].freeze

  scope :humans, -> { where.not(device: "bot") }

  BOT_RE = /bot|crawl|spider|slurp|facebookexternalhit|preview|headless|curl|wget|python|go-http|java\/|okhttp|yandex|bing|google|semrush|ahrefs|petal|duckduck/i

  # Mengekstrak atribut dari env request; dipanggil di controller (cepat, tanpa DB), lalu diserahkan ke job.
  def self.attributes_from(request, instance:, kind:, provider: nil, drama_id: nil)
    ua = request.user_agent.to_s
    ip = request.remote_ip.to_s
    {
      instance_id: instance.id,
      visitor_id: Digest::SHA256.hexdigest("#{ip}|#{ua}|#{instance.id}|#{Date.current}")[0, 32],
      path: request.fullpath.to_s[0, 300],
      kind: KINDS.include?(kind.to_s) ? kind.to_s : "other",
      provider: provider.to_s.presence&.first(40),
      drama_id: drama_id.to_s.presence&.first(80),
      country: request.headers["CF-IPCountry"].to_s.upcase.presence&.first(2),
      device: device_of(ua),
      os: os_of(ua),
      browser: browser_of(ua),
      referrer_host: referrer_host_of(request.referer, request.host),
      ip_prefix: ip_prefix_of(ip),
      user_agent: ua[0, 300],
      created_at: Time.current
    }
  end

  def self.device_of(ua)
    return "bot" if ua.blank? || ua.match?(BOT_RE)
    return "tablet" if ua.match?(/iPad|Tablet|Kindle|Silk|PlayBook/i) || (ua.include?("Android") && !ua.include?("Mobile"))
    return "mobile" if ua.match?(/Mobi|iPhone|iPod|Android|Opera Mini|IEMobile|BlackBerry/i)
    "desktop"
  end

  def self.os_of(ua)
    case ua
    when /iPhone|iPad|iPod/   then "iOS"
    when /Android/            then "Android"
    when /Windows/            then "Windows"
    when /Mac OS X|Macintosh/ then "macOS"
    when /CrOS/               then "ChromeOS"
    when /Linux/              then "Linux"
    else "Lainnya"
    end
  end

  def self.browser_of(ua)
    case ua
    when /Edg\//                       then "Edge"
    when /OPR\/|Opera/                 then "Opera"
    when /SamsungBrowser/              then "Samsung"
    when /MiuiBrowser/                 then "Mi Browser"
    when /UCBrowser/                   then "UC"
    when /FBAN|FBAV|Instagram|TikTok/  then "In-app"
    when /Firefox/                     then "Firefox"
    when /Chrome|CriOS/                then "Chrome"
    when /Safari/                      then "Safari"
    else "Lainnya"
    end
  end

  def self.referrer_host_of(ref, own_host)
    h = URI.parse(ref.to_s).host.to_s.downcase.delete_prefix("www.") rescue ""
    return nil if h.blank? || h == own_host.to_s.downcase.delete_prefix("www.")
    h[0, 120]
  end

  def self.ip_prefix_of(ip)
    addr = IPAddr.new(ip) rescue nil
    return nil unless addr
    addr.ipv4? ? addr.mask(24).to_s + "/24" : addr.mask(48).to_s + "/48"
  end
end

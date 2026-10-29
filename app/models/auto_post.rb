# Konfigurasi auto posting per instance per platform (saat ini: Instagram).
# cookies: [ { "label" => "nama akun", "cookie" => "sessionid=...; ds_user_id=...; ..." } ] — satu entri = satu akun;
# input mentah boleh berupa header Cookie, JSON ekspor Cookie-Editor, atau format Netscape (dinormalisasi ke header).
# Logika pengiriman postingan belum ada: record ini hanya menyimpan pengaturan + jadwal (next_run_at).
class AutoPost < ApplicationRecord
  PLATFORMS = %w[instagram].freeze
  MIN_INTERVAL = 5
  MAX_INTERVAL = 7 * 24 * 60

  belongs_to :instance

  validates :platform, inclusion: { in: PLATFORMS }
  validates :interval_minutes, numericality: { only_integer: true, greater_than_or_equal_to: MIN_INTERVAL, less_than_or_equal_to: MAX_INTERVAL }
  validate :enabled_requirements
  validate :cookies_have_session

  before_save :schedule_next_run

  def cookies = Array(super).select { |c| c.is_a?(Hash) && c["cookie"].present? }

  # raw: Array atau Hash berindeks dari form ({ "0" => { "label" => , "cookie" => }, ... }).
  def cookies=(raw)
    rows = raw.is_a?(Hash) ? raw.sort_by { |k, _| k.to_s.to_i }.map(&:last) : Array(raw)
    items = rows.filter_map do |r|
      h = r.respond_to?(:to_h) ? r.to_h.stringify_keys : {}
      cookie = self.class.normalize_cookie(h["cookie"])
      next if cookie.blank?
      { "label" => h["label"].to_s.strip.first(60).presence || self.class.account_label(cookie), "cookie" => cookie }
    end
    super(items)
  end

  def provider = provider_slug.present? ? Provider.find_by(slug: provider_slug) : nil
  def accounts_count = cookies.size

  # Header Cookie / JSON [{name,value}] / Netscape (7 kolom tab) → "a=b; c=d".
  def self.normalize_cookie(text)
    s = text.to_s.strip
    return "" if s.empty?
    pairs =
      if s.start_with?("[", "{")
        arr = JSON.parse(s)
        arr = arr["cookies"] if arr.is_a?(Hash) && arr["cookies"].is_a?(Array)
        Array(arr).filter_map { |c| c.is_a?(Hash) && c["name"].present? ? [ c["name"].to_s, c["value"].to_s ] : nil }
      elsif s.lines.any? { |l| l.split("\t").size >= 7 }
        s.lines.filter_map { |l| cols = l.chomp.split("\t"); cols.size >= 7 && !l.start_with?("#") ? [ cols[5], cols[6] ] : nil }
      else
        s.sub(/\Acookie:\s*/i, "").split(/;\s*|\r?\n/).filter_map { |kv| k, v = kv.split("=", 2); k.present? && v ? [ k.strip, v.strip ] : nil }
      end
    pairs.uniq { |k, _| k }.map { |k, v| "#{k}=#{v}" }.join("; ")
  rescue JSON::ParserError
    s.gsub(/\s+/, " ")
  end

  def self.cookie_value(cookie, name) = cookie.to_s[/(?:\A|;\s*)#{Regexp.escape(name)}=([^;]*)/, 1]
  def self.account_label(cookie) = (id = cookie_value(cookie, "ds_user_id")).present? ? "IG ##{id}" : "Akun"

  private
  def enabled_requirements
    return unless enabled?
    errors.add(:base, I18n.t("admin.auto_post.drama_required")) if provider_slug.blank? || drama_id.blank?
    errors.add(:base, I18n.t("admin.auto_post.cookies_required")) if cookies.empty?
  end

  def cookies_have_session
    cookies.each_with_index do |c, i|
      errors.add(:base, I18n.t("admin.auto_post.cookie_invalid", n: i + 1)) if self.class.cookie_value(c["cookie"], "sessionid").blank?
    end
  end

  def schedule_next_run
    self.next_run_at = enabled? ? (next_run_at.presence || Time.current + interval_minutes.minutes) : nil
    self.next_run_at = Time.current + interval_minutes.minutes if enabled? && will_save_change_to_interval_minutes?
  end
end

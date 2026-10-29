# Mengisi otomatis SEO instance (judul, meta, konten 500–800 kata, navbar, font, footer, tentang)
# dari target keyword via TokenPlus. Hasil langsung disimpan ke settings instance.
class SeoGenerator
  class Error < StandardError; end

  ALLOWED_PAGES = [ "/", "/latest", "/genre", "/search" ].freeze
  GENRE_PAGES = Template::V1::BaseController::GENRES.map { |g| "/genre/#{g}" }.freeze

  def initialize(instance, client: TokenPlusClient.from_settings, locale: I18n.default_locale)
    @instance = instance
    @client = client
    @locale = locale.to_s
  end

  def call
    keywords = @instance.seo_keyword_list
    raise Error, I18n.t("tokenplus.keywords_missing") if keywords.empty?
    provs = Provider.enabled.supported.by_latency.to_a.first(6).map(&:name)
    keywords = (keywords + provs.flat_map { |n| [ "Nonton #{n}", "Streaming #{n} sub indo" ] }).uniq.first(20)
    raw = @client.chat([ { role: "system", content: system_prompt }, { role: "user", content: user_prompt(keywords) } ], temperature: 0.85, max_tokens: 6000, json: true)
    data = parse_json(raw)
    apply!(data)
    data
  rescue TokenPlusClient::Error => e
    raise Error, e.message
  end

  private
  def lang_name = @locale == "en" ? "English" : "Bahasa Indonesia"

  def system_prompt
    <<~TXT
      You are a senior SEO copywriter for streaming websites (short Chinese/Asian dramas with subtitles).
      Always answer with ONE valid JSON object only, no markdown fences, no commentary.
      Write all human-readable text in #{lang_name}. Never mention login, account, registration, VIP or payment.

      WRITING STYLE — must read like a real person wrote it, not an AI:
      - Conversational, warm, second person ("kamu"/"you"), with concrete examples (name a typical plot, a typical binge moment).
      - Vary sentence length; mix short punchy lines with longer ones. Use contractions and everyday phrasing.
      - No filler or clichés: never write "dalam era digital", "di dunia yang serba cepat", "tak dapat dipungkiri", "in today's fast-paced world", "unlock", "elevate", "seamless", "delve", "dive into", "revolutionary", "game-changer".
      - No keyword stuffing: each keyword appears naturally at most 2–3 times across the whole article. Prefer synonyms and natural variations.
      - Avoid starting consecutive paragraphs the same way. Avoid lists of adjectives. One <ul> list max, 4–6 items, each item a full sentence.
      - Write like a helpful friend who watches a lot of short dramas, not like a brochure.
    TXT
  end

  def user_prompt(keywords)
    site = @instance.app_name.presence || @instance.display_name
    fonts = InstanceTheme::THEME_FONTS.keys.join(", ")
    pages = (ALLOWED_PAGES + GENRE_PAGES).join(", ")
    <<~TXT
      Site name: "#{site}". Current template: #{@instance.template_key}.
      Target keywords (use all naturally, primary first): #{keywords.join(" | ")}.

      Produce JSON with exactly these keys:
      {
        "site_title": "SEO title tag, max 65 characters, contains primary keyword and site name",
        "meta_description": "max 155 characters, persuasive, contains primary keyword",
        "app_name": "short brand name max 18 chars (keep \\"#{site}\\" unless clearly better)",
        "footer_text": "one-sentence tagline max 120 chars",
        "footer_about": "short about paragraph, 2–3 sentences, max 320 chars",
        "seo_content": "HTML article of 500–800 words: one <h2> headline, 4–6 sections with <h3>, <p>, one <ul> list. Cover what the site offers, how to watch (free, subtitles, HD, mobile), popular genres, why choose this site, FAQ-like tips. Use keywords naturally (no stuffing). No <h1>, no <script>, no inline styles, no external links.",
        "nav": [ {"label": "...", "url": "..."} ],
        "footer_links": [ {"label": "...", "url": "..."} ],
        "font": "one of: #{fonts}"
      }
      Rules for "nav": 4–6 items, url must be one of: #{pages}. First item must be "/" (home).
      Rules for "footer_links": 3–5 items, same allowed urls.
    TXT
  end

  def parse_json(raw)
    s = raw.to_s.strip.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
    s = s[s.index("{")..s.rindex("}")] if s.index("{") && s.rindex("}")
    JSON.parse(s)
  rescue JSON::ParserError, TypeError
    raise Error, I18n.t("tokenplus.bad_json")
  end

  def apply!(d)
    i = @instance
    # Teks per bahasa ditulis ke key "<key>_<locale>" bila locale bukan bawaan (lihat Instance#localized).
    set = ->(key, val) { i.public_send("#{i.localized_key(key, @locale)}=", val) }
    set.("site_title",       d["site_title"].to_s.strip.truncate(70, omission: ""))        if d["site_title"].present?
    set.("meta_description", d["meta_description"].to_s.strip.truncate(160, omission: "")) if d["meta_description"].present?
    i.app_name         = d["app_name"].to_s.strip.truncate(24, omission: "")          if d["app_name"].present? && i.app_name.blank?
    set.("footer_text",      d["footer_text"].to_s.strip.truncate(160, omission: ""))      if d["footer_text"].present?
    set.("footer_about",     d["footer_about"].to_s.strip.truncate(400, omission: ""))     if d["footer_about"].present?
    set.("seo_content",      d["seo_content"].to_s.strip)                                   if d["seo_content"].present?
    i.theme_font       = d["font"].to_s.strip.downcase if InstanceTheme::THEME_FONTS.key?(d["font"].to_s.strip.downcase)
    nav = clean_links(d["nav"]); i.nav_items = nav.map { |l| l.merge("enabled" => true) } if nav.size >= 2
    fl  = clean_links(d["footer_links"]); i.footer_links = fl if fl.any?
    i.seo_generated_at = Time.current.iso8601
    i.save!
  end

  def clean_links(arr)
    allowed = ALLOWED_PAGES + GENRE_PAGES
    Array(arr).filter_map do |it|
      next unless it.is_a?(Hash)
      url = it["url"].to_s.strip; label = it["label"].to_s.strip
      next if label.blank? || !allowed.include?(url)
      { "label" => label.truncate(24, omission: ""), "url" => url }
    end.uniq { |l| l["url"] }.first(6)
  end
end

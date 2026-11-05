module AutoPoster
  # Caption Instagram untuk satu akun AutoPost. Susunan:
  #   "Judul — Episode N [Part x/y]"  →  deskripsi + CTA  →  teks tetap akun  →  hashtag
  # Deskripsi+CTA dan hashtag dibuat SEKALI per judul lewat TokenPlus dan disimpan di auto_post
  # (caption_template / caption_tags); tiap episode hanya baris judul yang berubah sehingga API tidak dipanggil
  # berulang. Bila TokenPlus tidak dikonfigurasi/gagal, dipakai fallback dari data drama (tidak disimpan, supaya
  # dicoba lagi di siklus berikutnya).
  class CaptionWriter
    MAX_LEN = 2000 # batas IG 2200; sisakan ruang
    BASE_TAGS = %w[#fyp #fypシ #foryou #foryoupage #viral #reels #reelsinstagram #dracin #dramachina #dramacina #dramapendek #shortdrama #cdrama #nontondrama #sinopsisdrama].freeze

    def initialize(auto_post, drama, episode_number, part: 1, parts: 1, locale: "id", max_len: MAX_LEN)
      @ap, @instance, @drama, @ep, @part, @parts, @locale, @max_len = auto_post, auto_post.instance, drama, episode_number, part, parts, locale.to_s, max_len
    end

    def call
      generate_template if @ap.caption_template.blank?
      body = @ap.caption_template.presence || fallback_body
      tags = @ap.caption_tags.presence || fallback_tags
      finalize([ title_line, body, @ap.fixed_text, tags ].map { |s| s.to_s.strip }.reject(&:blank?).join("\n\n"))
    end

    private
    def title_line
      t = "#{@drama.title} — Episode #{@ep}"
      @parts.to_i > 1 ? "#{t} Part #{@part}/#{@parts}" : t
    end

    def generate_template
      client = TokenPlusClient.from_settings
      return unless client.configured?
      data = JSON.parse(client.chat([ { role: "system", content: system_prompt }, { role: "user", content: user_prompt } ], temperature: 0.8, max_tokens: 1500, json: true))
      body = [ data["body"], data["cta"] ].map { |s| s.to_s.strip }.reject(&:blank?).join("\n\n")
      tags = Array(data["hashtags"]).map { |t| "#" + t.to_s.delete("#").gsub(/[^\p{Alnum}_]/, "") }.reject { |t| t.size < 3 }
      return if body.blank?
      @ap.update_columns(caption_template: body, caption_tags: (tags + BASE_TAGS).uniq.first(28).join(" "))
    rescue TokenPlusClient::Error, JSON::ParserError => e
      Rails.logger.warn("[AutoPoster] caption TokenPlus: #{e.class} #{e.message}")
    end

    def system_prompt
      lang = @locale == "en" ? "English" : "Bahasa Indonesia"
      <<~P
        You write Instagram Reels captions for short Chinese drama clips. Language: #{lang}. Tone: hooky, casual, emotional, 1-3 emojis max, no clickbait lies.
        The caption is reused for every episode of the drama, so describe the drama's premise in general and NEVER mention a specific episode number.
        Return ONLY JSON: {"body": "<2-4 short sentences explaining the premise / why to watch, max 350 chars>", "cta": "<1 sentence inviting to watch full episodes on the site named>", "hashtags": ["10-14 lowercase hashtags without #; mix of FYP/viral tags, drama-china tags, and tags from the title/genre"]}
      P
    end

    def user_prompt
      {
        title: @drama.title, total_episodes: @drama.episodes, genres: Array(@drama.genres).first(6),
        synopsis: @drama.synopsis.to_s.first(700), site_name: @instance.display_name, site_url: @instance.public_url
      }.to_json
    end

    def fallback_body
      syn = @drama.synopsis.to_s.squish.first(300)
      cta = @locale == "en" ? "Watch all episodes free on #{@instance.display_name}: #{@instance.public_url}" : "Nonton semua episode gratis di #{@instance.display_name}: #{@instance.public_url}"
      [ syn, cta ].reject(&:blank?).join("\n\n")
    end

    def fallback_tags
      tags = Array(@drama.genres).map { |g| "#" + g.to_s.downcase.gsub(/[^\p{Alnum}]/, "") }.reject { |t| t.size < 3 }
      (tags + BASE_TAGS).uniq.first(28).join(" ")
    end

    def finalize(text)
      t = text.to_s.strip.gsub(/\r\n?/, "\n").gsub(/\n{3,}/, "\n\n")
      t.size > @max_len ? t[0, @max_len].sub(/\s+\S*\z/, "") : t
    end
  end
end

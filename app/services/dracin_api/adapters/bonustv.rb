module DracinApi
  module Adapters
    # https://bonustv.goodbos.online — token lewat header x-token (endpoint dipakai frontend "Tonton")
    #   /api/v1/home/modules?lang=      → { data: [ { title, videos: [d] } ] }
    #   /api/v1/recommend?page=&lang=   → { data: { data: [d], page_info } }
    #   /api/v1/search?q=&page=&lang=   → { data: { data: [d], page_info: { count, page, total } } }
    #   /api/v1/detail/:id?lang=        → { data: { id, title, description, cover, tags, total_episodes, status } }
    #   /api/v1/episodes/:id?lang=      → { data: [...] }  (sering balas code 901 → fallback dari total_episodes)
    #   /api/v1/episode/:id/:ep?lang=   → { data: { hls_url, duration, resolution, unlock } }
    class Bonustv < Base
      default_host "https://bonustv.goodbos.online"
      PAGE_SIZE = 20

      def home
        mods = begin
          Array(ok(get("/api/v1/home/modules", lang: lang))["data"])
        rescue DracinApi::HttpError
          [] # modules upstream sering 502 → pakai recommend
        end
        secs = mods.filter_map do |m|
          items = Array(m["videos"]).filter_map { |d| to_drama(d) }
          items.any? ? section(m["title"].to_s.strip.presence || I18n.t("template.v1.sections.for_you"), items) : nil
        end
        return secs if secs.any?
        rec = ok(get("/api/v1/recommend", page: 1, lang: lang)).dig("data", "data")
        [ section(I18n.t("template.v1.sections.for_you"), Array(rec).filter_map { |d| to_drama(d) }) ]
      end

      def search(q, page: 1)
        data = ok(get("/api/v1/search", q: q, page: page, lang: lang))["data"]
        list = data.is_a?(Hash) ? Array(data["data"]) : Array(data)
        info = data.is_a?(Hash) ? (data["page_info"] || {}) : {}
        has_more = info["total"].to_i > page.to_i * PAGE_SIZE || list.size >= PAGE_SIZE && info["total"].to_i.zero?
        page(list.filter_map { |d| to_drama(d) }, page: page, has_more: has_more)
      end

      def detail(id)
        d = ok(get("/api/v1/detail/#{id}", lang: lang))["data"]
        to_drama(d, id) || drama(id: id, title: "—")
      end

      def episodes(id)
        resp = get("/api/v1/episodes/#{id}", lang: lang)
        list = resp["code"].to_i == 200 ? Array(resp["data"].is_a?(Hash) ? (resp["data"]["data"] || resp["data"]["episodes"]) : resp["data"]) : []
        if list.any?
          list.each_with_index.map do |e, i|
            num = (e["episode"] || e["episode_num"] || e["order"] || e["index"] || (i + 1)).to_i
            episode(number: num, title: "EP #{num}", thumbnail: e["cover"], duration: seconds_to_clock(e["duration"]), locked: false, payload: e)
          end.sort_by(&:number)
        else
          total = detail(id).episodes.to_i
          (1..total).map { |n| episode(number: n, title: "EP #{n}", thumbnail: nil, duration: nil, locked: false, payload: {}) }
        end
      end

      def play(id, ep)
        v = ok(get("/api/v1/episode/#{id}/#{ep}", lang: lang))["data"]
        return nil unless v.is_a?(Hash)
        return nil if v["unlock"] == false
        url = v["hls_url"].presence || v["url"].presence || v["video_url"].presence
        return nil if url.blank?
        label = v["resolution"].to_s.presence
        stream(url: url, episode: ep, sources: (label ? [ { label: label, url: url } ] : nil))
      end

      private
      # Upstream membalas { code: 901 } (rate-limit/kosong) tanpa pesan — jadikan hash kosong agar fallback jalan.
      def ok(resp)
        return {} unless resp.is_a?(Hash)
        resp["code"].to_i.between?(200, 299) || resp["code"].nil? ? resp : {}
      end

      def to_drama(d, fallback_id = nil)
        return nil unless d.is_a?(Hash)
        d = d["video"] if d["video"].is_a?(Hash)
        id = d["id"] || d["video_id"] || fallback_id
        return nil if id.blank?
        drama(id: id, title: d["title"].to_s.strip, cover: d["cover"] || d["image"], synopsis: d["description"].to_s.strip.presence,
              genres: Array(d["tags"] || d["genre"]).map(&:to_s).reject(&:blank?).first(5),
              episodes: (d["total_episodes"] || d["episode_total_num"]).to_i.nonzero?, language: d["language"].presence,
              rating: nil, year: nil, status: nil)
      end
    end
  end
end

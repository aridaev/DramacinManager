module DracinApi
  module Adapters
    # https://raptdrama.goodbos.online — token lewat header x-token
    #   /api/raptdrama/home                → { data: { trending: [d], new_releases: [d], featured: [ { video: d } ], recommend: [d] } }
    #   /api/raptdrama/search?query=&page= → { data: { results: [d] } }
    #   /api/raptdrama/detail?id=          → { data: { id, title, image, desc, total_episodes, score, forstausen, classify } }
    #   /api/raptdrama/episodes?id=        → { data: { vid, total, episodes: [ { episode|index, url|hls|m3u8, title } ] } }
    #   d = { id, title, image, desc, total_episodes|totalvideo, score, forstausen, classify: [genre] }
    class Raptdrama < Base
      default_host "https://raptdrama.goodbos.online"
      PAGE_SIZE = 15

      def home
        data = get("/api/raptdrama/home")["data"]
        return [] unless data.is_a?(Hash)
        {
          "trending"     => I18n.t("template.v1.sections.trending", default: "Trending"),
          "new_releases" => I18n.t("template.v1.sections.new", default: "Terbaru"),
          "recommend"    => I18n.t("template.v1.sections.for_you"),
          "featured"     => I18n.t("template.v1.sections.featured", default: "Pilihan")
        }.filter_map do |key, title|
          items = Array(data[key]).filter_map { |d| raw = d.is_a?(Hash) && d["video"].is_a?(Hash) ? d["video"] : d; to_drama(raw) }
          items.any? ? section(title, items) : nil
        end
      end

      def search(q, page: 1)
        data = get("/api/raptdrama/search", query: q, page: page)["data"]
        list = data.is_a?(Hash) ? Array(data["results"]) : Array(data)
        page(list.filter_map { |d| to_drama(d) }, page: page, has_more: list.size >= PAGE_SIZE)
      end

      def detail(id)
        d = get("/api/raptdrama/detail", id: id)["data"]
        d = d["video"] if d.is_a?(Hash) && d["video"].is_a?(Hash)
        return to_drama(d, id) if d.is_a?(Hash) && d.present?
        # Endpoint detail upstream kadang kosong → cari di home/search sebagai cadangan.
        home.flat_map(&:items).find { |x| x.id == id.to_s } || drama(id: id, title: "—")
      end

      def episodes(id)
        data = get("/api/raptdrama/episodes", id: id)["data"]
        list = data.is_a?(Hash) ? Array(data["episodes"] || data["list"]) : Array(data)
        list.each_with_index.map do |e, i|
          num = (e["episode"] || e["ep"] || e["index"] || e["sort"] || e["number"] || (i + 1)).to_i
          num = i + 1 if num <= 0
          episode(number: num, title: e["title"].presence || "EP #{num}", thumbnail: e["image"] || e["cover"],
                  duration: seconds_to_clock(e["duration"]), locked: e["lock"] == true || e["is_lock"] == 1, payload: e)
        end.sort_by(&:number)
      end

      def play(id, ep)
        e = find_episode(id, ep) or return nil
        return nil if e.locked
        raw = e.payload
        url = %w[hls m3u8 url video_url play_url video src].map { |k| raw[k] }.find(&:present?)
        return nil if url.blank?
        stream(url: url, episode: ep)
      end

      private
      def to_drama(d, fallback_id = nil)
        return nil unless d.is_a?(Hash)
        id = d["id"] || d["vid"] || fallback_id
        return nil if id.blank?
        eps = (d["total_episodes"] || d["totalvideo"] || d["total"]).to_i.nonzero?
        drama(id: id, title: CGI.unescapeHTML(d["title"].to_s), cover: d["image"] || d["cover"],
              synopsis: CGI.unescapeHTML(d["desc"].to_s).strip.presence, episodes: eps,
              genres: Array(d["classify"]).map(&:to_s).reject(&:blank?), language: nil,
              rating: d["score"].presence, year: nil, status: d["forstausen"].presence)
      end
    end
  end
end

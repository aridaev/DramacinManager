module DracinApi
  module Adapters
    # https://dramawave.goodbos.online — header x-token
    #   /api/home?lang=         → { data: [ { module_name, items: [ { playlet_id|id, name, cover, desc, episode_count, series_tag } ] } ] }
    #   /api/search?q=&lang=&page= → { list: [...], page_info: { has_more, page } }
    #   /api/drama/:id?lang=    → { data: { name, cover, episode_count, items: [ { serial_number, m3u8_path, 720p_mp4, subtitle_list, video_type } ] } }
    class Dramawave < Base
      default_host "https://dramawave.goodbos.online"

      def home
        Array(get("/api/home", lang: lang)["data"]).filter_map do |mod|
          items = Array(mod["items"]).map { |d| to_drama(d) }
          next if items.empty?
          section(mod["module_name"].presence || I18n.t("template.v1.sections.featured"), items)
        end
      end

      def search(q, page: 1)
        data = get("/api/search", q: q, lang: lang, page: page)
        items = Array(data["list"]).map { |d| to_drama(d) }
        page(items, page: data.dig("page_info", "page") || page, has_more: data.dig("page_info", "has_more"))
      end

      def detail(id)
        d = drama_data(id)
        drama(id: id, title: d["name"], cover: d["cover"], synopsis: d["desc"], episodes: d["episode_count"].to_i.nonzero?,
              genres: Array(d["series_tag"]).first(5), language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(drama_data(id)["items"]).reject { |e| e["is_blooper"] }.map do |e|
          episode(number: e["serial_number"], title: "EP #{e['serial_number']}", thumbnail: e["cover"], duration: nil,
                  locked: false, payload: e)
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        e = item.payload
        url = e["m3u8_path"].presence || e["720p_mp4"].presence || e["1080p_mp4"].presence || e["540p_mp4"]
        return nil if url.blank?
        subs = Array(e["subtitle_list"]).map { |s| subtitle(lang: s["language"], label: s["display_name"], url: s["subtitle"]) }.select { |s| s[:url].present? }
        sources = sources_from(e, { "m3u8_path" => "Auto", "1080p_mp4" => "1080p", "720p_mp4" => "720p", "540p_mp4" => "540p" })
        stream(url: url, episode: ep, sources: sources, subtitles: subs)
      end

      private
      def drama_data(id) = get("/api/drama/#{id}", lang: lang)["data"] || {}

      def to_drama(d)
        drama(id: d["playlet_id"] || d["id"], title: d["name"], cover: d["cover"], synopsis: d["desc"], episodes: d["episode_count"].to_i.nonzero?,
              genres: Array(d["series_tag"]).first(5), language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end

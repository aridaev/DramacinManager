module DracinApi
  module Adapters
    # https://dramabite.goodbos.online — path TANPA prefix /api; katalog terbuka, play/episodes butuh ?code=KEY
    #   /home?lang=                 → { module_list: [ { module_id, module_name, module_item_list: [ { Item: { VideoInfo: { cid, title, cover_url, desc, total_episode, label_list } } } ] } ] }
    #   /module?lang=&page=         → { title, total, videos: [ { id, title, cover, tags } ] }   (page 1 = baru ditonton, 2 = rekomendasi)
    #   /search?q=&lang=            → [ { id, title, cover, desc, tags } ]
    #   /drama/:cid?lang=           → { id, title, desc, cover, episodes, tags }
    #   /episodes/:cid?lang=        → [ { vid, title, url (HLS, wsSecret ~ jam) } ]
    #   /play/:cid/:vid?lang=       → { url }   (URL segar)
    class Dramabite < Base
      default_host "https://dramabite.goodbos.online"

      def home
        home, rec = concurrently(-> { get("/home", lang: lang) }, -> { get("/module", lang: lang, page: 2) })
        sections = Array(home["module_list"]).filter_map do |m|
          items = Array(m["module_item_list"]).map { |it| it.dig("Item", "VideoInfo") }.compact.map { |v| to_drama(v) }
          section(m["module_name"].to_s.strip.presence || I18n.t("template.v1.sections.trending"), items) if items.any?
        end
        rec_items = Array(rec["videos"]).map { |v| to_drama(v) }
        sections << section(rec["title"].to_s.strip.presence || I18n.t("template.v1.sections.for_you"), rec_items) if rec_items.any?
        sections
      end

      def search(q, page: 1)
        page(Array(get("/search", q: q, lang: lang)).map { |v| to_drama(v) }, page: 1, has_more: false)
      end

      def detail(id)
        d = get("/drama/#{id}", lang: lang) || {}
        to_drama(d.merge("id" => d["id"] || id))
      end

      def episodes(id)
        Array(get("/episodes/#{id}", lang: lang)).map do |e|
          n = e["vid"].to_i
          episode(number: n, title: "EP #{n}", thumbnail: nil, duration: nil, locked: e["url"].blank?, payload: e.slice("vid", "url"))
        end
      end

      # URL di /episodes berumur pendek (wsTime); ambil URL segar dari /play.
      def play(id, ep)
        item = find_episode(id, ep) or return nil
        url = (get("/play/#{id}/#{item.payload['vid'] || ep}", lang: lang) || {})["url"].presence || item.payload["url"]
        return nil if url.blank?
        stream(url: url, episode: ep)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def to_drama(v)
        tags = Array(v["tags"].presence || v["label_list"]).map { |t| t.is_a?(Hash) ? (t["name"] || t["title"]) : t }.compact
        drama(id: v["cid"] || v["id"], title: v["title"].to_s.strip, cover: v["cover"] || v["cover_url"] || v["video_poster_url"], synopsis: v["desc"],
              genres: tags.first(5), episodes: (v["total_episode"] || v["episodes"]).to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end

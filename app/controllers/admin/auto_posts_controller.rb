# Auto posting Instagram per instance: halaman tersendiri (/admin/instances/:id/auto_posts), satu kartu per akun
# (cookie) dengan konten/jadwal masing-masing — boleh berbeda judul, boleh sama. Akses mengikuti
# Admin::InstancesController (admin semua instance, user hanya miliknya).
class Admin::AutoPostsController < ApplicationController
  layout "application"
  before_action :load_instance
  before_action :load_auto_post, only: [ :update, :destroy, :run_now ]

  PERMIT = [ :enabled, :label, :cookie, :provider_slug, :drama_id, :drama_title, :auto_title, :episodes_per_title, :interval_minutes, :max_seconds, :fixed_text ].freeze
  COPY_KEYS = %w[auto_title episodes_per_title interval_minutes max_seconds fixed_text].freeze

  def index
    @auto_posts = scope_posts.to_a
    @providers = Provider.enabled.supported.order(:position, :name)
  end

  # Tambah akun: textarea boleh berisi beberapa cookie (dipisah baris kosong / ---) → satu baris per akun.
  # Pengaturan konten disalin dari akun terakhir (bila ada) agar tinggal diubah bila ingin beda.
  def create
    blocks = AutoPost.split_cookies(params.dig(:auto_post, :cookie))
    return redirect_to(admin_instance_auto_posts_path(@instance), alert: t("admin.auto_post.cookie_required")) if blocks.empty?
    tpl = scope_posts.last
    created, errors = 0, []
    blocks.each_with_index do |c, i|
      ap = @instance.auto_posts.new(platform: "instagram", cookie: c, label: (params.dig(:auto_post, :label) if blocks.size == 1))
      tpl ? ap.assign_attributes(tpl.slice(*COPY_KEYS)) : ap.fixed_text = AutoPost::DEFAULT_FIXED_TEXT
      ap.save ? created += 1 : errors << "##{i + 1}: #{ap.errors.full_messages.join(', ')}"
    end
    flash[:notice] = t("admin.auto_post.added", n: created) if created.positive?
    flash[:alert] = errors.join(" · ") if errors.any?
    redirect_to admin_instance_auto_posts_path(@instance)
  end

  def update
    attrs = params.require(:auto_post).permit(PERMIT)
    attrs.delete(:cookie) if attrs[:cookie].blank? # kosong = pertahankan cookie lama
    @auto_post.assign_attributes(attrs)
    if @auto_post.save
      redirect_to admin_instance_auto_posts_path(@instance, anchor: "ap-#{@auto_post.id}"), notice: t("admin.auto_post.saved", label: @auto_post.label)
    else
      redirect_to admin_instance_auto_posts_path(@instance, anchor: "ap-#{@auto_post.id}"), alert: @auto_post.errors.full_messages.join(", ")
    end
  end

  def destroy
    @auto_post.destroy
    redirect_to admin_instance_auto_posts_path(@instance), notice: t("admin.auto_post.deleted", label: @auto_post.label)
  end

  # Antrekan satu siklus posting sekarang (tanpa menunggu jadwal) untuk uji akun/cookie.
  def run_now
    return redirect_to admin_instance_auto_posts_path(@instance, anchor: "ap-#{@auto_post.id}"), alert: t("admin.auto_post.run_now_incomplete") unless @auto_post.ready?
    @auto_post.update_columns(last_status: "antre…") unless @auto_post.last_status.to_s.start_with?("antre")
    InstagramPostJob.perform_later(@auto_post.id, manual: true)
    redirect_to admin_instance_auto_posts_path(@instance, anchor: "ap-#{@auto_post.id}"), notice: t("admin.auto_post.run_now_queued")
  end

  # Daftar judul untuk dropdown: beranda provider (+ hasil pencarian bila q diisi). JSON [{ id, title }].
  def dramas
    provider = Provider.enabled.supported.find_by(slug: params[:provider]) or return render(json: { items: [], error: t("admin.auto_post.provider_unknown") }, status: :unprocessable_entity)
    catalog = DracinApi::Catalog.for(provider)
    items = catalog.home.flat_map(&:items)
    items = catalog.search(params[:q].to_s.strip, page: 1).items + items if params[:q].to_s.strip.length >= 2
    render json: { items: items.uniq(&:id).first(300).map { |d| { id: d.id.to_s, title: d.title.to_s } } }
  rescue DracinApi::Error => e
    render json: { items: [], error: e.message }, status: :bad_gateway
  end

  private
  def load_instance
    scope = admin? ? Instance.all : Instance.where(created_by_id: current_user.id)
    @instance = scope.find(params[:instance_id])
  end

  def scope_posts = @instance.auto_posts.where(platform: "instagram").order(:id)
  def load_auto_post = @auto_post = scope_posts.find(params[:id])
end

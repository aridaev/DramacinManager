# Instance dapat diakses admin (semua) dan user (hanya miliknya). Rute tetap di /admin/instances,
# tetapi controller ini TIDAK mewarisi Admin::BaseController agar user biasa bisa masuk.
class Admin::InstancesController < ApplicationController
  layout "application"
  before_action :require_instance_access!
  before_action :load_instance, only: [ :show, :edit, :update, :destroy, :regenerate, :generate_seo, :submit_indexnow ]

  def index
    @instances = scope.ordered.includes(:created_by, :domains)
    @counts = scope.group(:status).count
  end

  def show
    @domains = @instance.domains.ordered
    @domain = Domain.new
    @cf_ready = CloudflareClient.from_settings.configured? && Setting.vps_ip.present?
  end

  # Create langsung: nama acak dibuat otomatis oleh model.
  def create
    unless admin?
      limit = Setting.max_instances_per_user
      if limit.positive? && scope.count >= limit
        return redirect_to admin_instances_path, alert: t("admin.instances.limit_reached", limit: limit)
      end
    end
    instance = Instance.create!(created_by: current_user)
    redirect_to edit_admin_instance_path(instance), notice: t("admin.instances.created", name: instance.name)
  end

  def edit; end

  def update
    @instance.assign_attributes(instance_params.except(:nav_items, :footer_links))
    @instance.nav_items = params.dig(:instance, :nav_items).to_unsafe_h if params.dig(:instance, :nav_items).present?
    @instance.footer_links = params.dig(:instance, :footer_links).to_unsafe_h if params.dig(:instance, :footer_links).present?
    if @instance.save
      redirect_to admin_instance_path(@instance), notice: t("admin.instances.updated", name: @instance.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Simpan isian form, lalu generate SEO via TokenPlus dari target keyword.
  def generate_seo
    @instance.assign_attributes(instance_params.except(:nav_items, :footer_links))
    @instance.nav_items = params.dig(:instance, :nav_items).to_unsafe_h if params.dig(:instance, :nav_items).present?
    @instance.footer_links = params.dig(:instance, :footer_links).to_unsafe_h if params.dig(:instance, :footer_links).present?
    return render(:edit, status: :unprocessable_entity) unless @instance.save
    return redirect_to edit_admin_instance_path(@instance, anchor: "sec-ai"), alert: t("tokenplus.keywords_missing") if @instance.seo_keyword_list.empty?
    client = TokenPlusClient.from_settings
    return redirect_to edit_admin_instance_path(@instance, anchor: "sec-ai"), alert: t("admin.instances.ai_not_configured") unless client.configured?
    SeoGenerator.new(@instance, client: client, locale: I18n.locale).call
    redirect_to edit_admin_instance_path(@instance, anchor: "sec-seo"), notice: t("admin.instances.ai_done", model: client.model)
  rescue SeoGenerator::Error, ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_instance_path(@instance, anchor: "sec-ai"), alert: t("admin.instances.ai_failed", error: e.message)
  end

  def submit_indexnow
    @instance.assign_attributes(instance_params.except(:nav_items, :footer_links)) if params[:instance].present?
    @instance.save if @instance.changed?
    host = @instance.primary_host
    return redirect_to edit_admin_instance_path(@instance, anchor: "sec-search"), alert: t("admin.instances.indexnow_need_domain") unless host
    r = IndexNowSubmitter.new(@instance, host: host).call
    redirect_to edit_admin_instance_path(@instance, anchor: "sec-search"), notice: t("admin.instances.indexnow_ok", count: r[:count], code: r[:code])
  rescue IndexNowSubmitter::Error => e
    redirect_to edit_admin_instance_path(@instance, anchor: "sec-search"), alert: t("admin.instances.indexnow_failed", error: e.message)
  end

  def regenerate
    @instance.update!(name: Instance.random_name)
    redirect_to admin_instance_path(@instance), notice: t("admin.instances.regenerated", name: @instance.name)
  end

  def destroy
    @instance.destroy
    redirect_to admin_instances_path, notice: t("admin.instances.deleted", name: @instance.name)
  end

  private
  # Admin: semua instance. User: hanya yang dia buat.
  def scope = admin? ? Instance.all : Instance.where(created_by_id: current_user.id)

  def load_instance = @instance = scope.find(params[:id])

  def require_instance_access!
    return if admin? || Setting.users_can_create_instances?
    redirect_to root_path, alert: t("admin.instances.access_disabled")
  end

  def instance_params
    permitted = [ :title, :notes, *Instance::SETTING_KEYS, *InstanceTheme::THEME_KEYS ]
    permitted << :status if admin?
    params.require(:instance).permit(*permitted)
  end
end

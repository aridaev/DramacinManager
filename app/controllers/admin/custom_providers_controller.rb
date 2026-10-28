# Provider buatan admin: menunjuk host API sendiri dan memilih adapter (skema) yang sudah ada.
# Berguna saat penyedia lain mengekspos API dengan skema sama (mis. mirror DramaBox di host berbeda).
class Admin::CustomProvidersController < Admin::BaseController
  before_action :load_provider, only: [ :edit, :update, :destroy ]

  def new
    @provider = Provider.new(custom: true, enabled: true, category: :short_drama, api_source: ApiSource.default)
  end

  def create
    @provider = Provider.new(provider_params.merge(custom: true, position: (Provider.maximum(:position) || 0) + 1))
    if @provider.save
      redirect_to admin_providers_path, notice: t("admin.custom_providers.created", name: @provider.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = provider_params
    attrs.delete(:api_key) if attrs[:api_key].blank?
    if @provider.update(attrs)
      redirect_to admin_providers_path, notice: t("admin.custom_providers.updated", name: @provider.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @provider.destroy
    redirect_to admin_providers_path, notice: t("admin.custom_providers.deleted", name: @provider.name)
  end

  private
  def load_provider = @provider = Provider.find(params[:id])

  def provider_params
    params.require(:provider).permit(:name, :slug, :category, :api_url, :logo_url, :adapter_key, :api_source_id, :auth_mode, :api_key, :enabled, :notes)
  end
end

class AddRecoveryCheckToProviders < ActiveRecord::Migration[8.0]
  def change
    # Hasil cek pemulihan berkala (ProviderRecoveryCheckJob) untuk penyedia yang sedang disembunyikan.
    add_column :providers, :recovery_checked_at, :datetime
    add_column :providers, :recovery_result, :string
  end
end

class AddGoogleCalendarPaymentReminders < ActiveRecord::Migration[8.1]
  def up
    add_column :entries, :completed_on, :date
    add_column :users, :google_calendar_id, :string
    add_column :users, :google_refresh_token_ciphertext, :text
    add_column :users, :google_access_token_ciphertext, :text
    add_column :users, :google_access_token_expires_at, :datetime
    add_column :users, :google_calendar_sync_error, :text
    execute "UPDATE entries SET completed_on = date WHERE status = 'actual'"
  end

  def down
    remove_column :entries, :completed_on
    remove_column :users, :google_calendar_id
    remove_column :users, :google_refresh_token_ciphertext
    remove_column :users, :google_access_token_ciphertext
    remove_column :users, :google_access_token_expires_at
    remove_column :users, :google_calendar_sync_error
  end
end

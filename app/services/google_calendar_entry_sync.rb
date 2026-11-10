class GoogleCalendarEntrySync
  def self.with_api_factory(factory)
    previous = @api_factory
    @api_factory = factory
    yield
  ensure
    @api_factory = previous
  end

  def self.build_api(user)
    (@api_factory || ->(record) { GoogleCalendarApi.new(record) }).call(user)
  end

  def self.callbacks_suppressed?
    Thread.current[:skip_google_calendar_entry_callbacks]
  end

  def self.suppress_callbacks
    previous = Thread.current[:skip_google_calendar_entry_callbacks]
    Thread.current[:skip_google_calendar_entry_callbacks] = true
    yield
  ensure
    Thread.current[:skip_google_calendar_entry_callbacks] = previous
  end

  def self.call(entry_id, transitioned_to_actual: false)
    user = User.where.not(google_calendar_id: nil).first
    return unless user&.google_calendar_connected?

    entry = Entry.find_by(id: entry_id)
    return remove(entry_id) unless entry

    api = build_api(user)
    api.ensure_calendar!

    if payable?(entry)
      sync_pending(api, entry)
    elsif entry.status == 'actual' && entry.kind == 'expense'
      sync_paid(api, entry, transitioned_to_actual: transitioned_to_actual)
    else
      remove_events(api, entry.id)
    end

    user.update_column(:google_calendar_sync_error, nil)
  end

  def self.remove(entry_id)
    user = User.where.not(google_calendar_id: nil).first
    return unless user&.google_calendar_connected?

    api = build_api(user)
    remove_events(api, entry_id)
  end

  def self.sync_all
    user = User.where.not(google_calendar_id: nil).first
    return unless user&.google_calendar_connected?

    api = build_api(user)
    api.ensure_calendar!
    existing_events = Hash.new { |hash, key| hash[key] = [] }
    api.each_app_event do |event|
      entry_id = event.dig('extendedProperties', 'private', 'entry_id').to_i
      existing_events[entry_id] << event.fetch('id') if entry_id.positive?
    end
    Entry.find_each do |entry|
      if payable?(entry)
        sync_pending(api, entry)
      elsif entry.kind == 'expense' && entry.status == 'actual' && existing_events.key?(entry.id)
        sync_paid(api, entry, transitioned_to_actual: false)
      elsif existing_events.key?(entry.id)
        remove_events(api, entry.id)
      end
      existing_events.delete(entry.id)
    end
    existing_events.each_value { |event_ids| event_ids.each { |event_id| api.delete_event(event_id) } }
    user.update_column(:google_calendar_sync_error, nil)
  end

  def self.pending_event_id(entry_id) = google_event_id('a', entry_id)
  def self.reminder_13_event_id(entry_id) = google_event_id('b', entry_id)
  def self.reminder_19_event_id(entry_id) = google_event_id('c', entry_id)
  def self.paid_event_id(entry_id) = google_event_id('d', entry_id)

  def self.google_event_id(prefix, entry_id)
    "#{prefix}#{entry_id.to_s(32).rjust(5, '0')}"
  end
  private_class_method :google_event_id

  def self.payable?(entry)
    entry.kind == 'expense' && entry.status == 'planned'
  end
  private_class_method :payable?

  def self.sync_pending(api, entry)
    today = Date.current
    due_date = entry.date
    display_start = [due_date, today].max
    summary = due_date < today ? "Pagamento vencido · #{entry.description}" : "Pagamento · #{entry.description}"
    details = "Valor: #{ActionController::Base.helpers.number_to_currency(entry.amount, unit: 'R$', separator: ',', delimiter: '.') }\nVencimento: #{I18n.l(due_date)}\nCategoria: #{entry.category.name}"

    api.delete_event(paid_event_id(entry.id))
    api.upsert_event(pending_event_id(entry.id), {
      summary: summary,
      description: details,
      start: { date: display_start.iso8601 },
      end: { date: (display_start + 1.day).iso8601 },
      recurrence: ['RRULE:FREQ=DAILY'],
      transparency: 'transparent',
      reminders: { useDefault: false, overrides: [] },
      extendedProperties: private_properties(entry.id, 'payment')
    })

    reminder_start = [due_date - 3.days, today].max
    sync_reminder(api, entry, event_id: reminder_13_event_id(entry.id), hour: 13, start_date: reminder_start, details: details)
    sync_reminder(api, entry, event_id: reminder_19_event_id(entry.id), hour: 19, start_date: reminder_start, details: details)
  end
  private_class_method :sync_pending

  def self.sync_reminder(api, entry, event_id:, hour:, start_date:, details:)
    start_time = Time.zone.local(start_date.year, start_date.month, start_date.day, hour, 0, 0)
    start_time = start_time + 1.day if start_time <= Time.current
    end_time = start_time + 5.minutes
    api.upsert_event(event_id, {
      summary: "Lembrete de pagamento · #{entry.description}",
      description: "Ainda consta como pendente no app.\n#{details}",
      start: { dateTime: start_time.iso8601, timeZone: 'America/Sao_Paulo' },
      end: { dateTime: end_time.iso8601, timeZone: 'America/Sao_Paulo' },
      recurrence: ['RRULE:FREQ=DAILY'],
      transparency: 'transparent',
      reminders: { useDefault: false, overrides: [{ method: 'popup', minutes: 0 }] },
      extendedProperties: private_properties(entry.id, "reminder_#{hour}")
    })
  end
  private_class_method :sync_reminder

  def self.sync_paid(api, entry, transitioned_to_actual:)
    pending_exists = api.get_event(pending_event_id(entry.id)).present?
    reminder_exists = api.get_event(reminder_13_event_id(entry.id)).present? || api.get_event(reminder_19_event_id(entry.id)).present?
    paid_exists = api.get_event(paid_event_id(entry.id)).present?
    if pending_exists || reminder_exists || transitioned_to_actual || paid_exists
      remove_pending_events(api, entry.id)
      paid_date = entry.completed_on || entry.date
      details = "Pagamento registrado no app.\nValor: #{ActionController::Base.helpers.number_to_currency(entry.amount, unit: 'R$', separator: ',', delimiter: '.') }\nVencimento: #{I18n.l(entry.date)}"
      api.upsert_event(paid_event_id(entry.id), {
        summary: "Pago · #{entry.description}",
        description: details,
        start: { date: paid_date.iso8601 },
        end: { date: (paid_date + 1.day).iso8601 },
        transparency: 'transparent',
        reminders: { useDefault: false, overrides: [] },
        extendedProperties: private_properties(entry.id, 'paid')
      })
    end
  end
  private_class_method :sync_paid

  def self.remove_pending_events(api, entry_id)
    [pending_event_id(entry_id), reminder_13_event_id(entry_id), reminder_19_event_id(entry_id)].each do |event_id|
      api.delete_event(event_id)
    end
  end
  private_class_method :remove_pending_events

  def self.remove_events(api, entry_id)
    [pending_event_id(entry_id), reminder_13_event_id(entry_id), reminder_19_event_id(entry_id), paid_event_id(entry_id)].each do |event_id|
      api.delete_event(event_id)
    end
  end
  private_class_method :remove_events

  def self.private_properties(entry_id, type)
    { private: { app: 'fluxo_de_caixa', entry_id: entry_id.to_s, type: type } }
  end
  private_class_method :private_properties
end

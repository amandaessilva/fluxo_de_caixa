require 'test_helper'
class FlowsTest < ActionDispatch::IntegrationTest
  setup { setup_finances }
  test 'todas as rotas financeiras exigem autenticação' do
    [root_path, entries_path, categories_path, annual_path, settings_path, new_import_path, backup_path].each do |path|
      get path
      assert_redirected_to new_session_path
    end
  end
  test 'páginas principais e formulários renderizam em português' do
    sign_in
    [root_path, entries_path, categories_path, annual_path, settings_path, new_import_path, new_entry_path, new_category_path].each do |path|
      get path
      assert_response :success
      assert_select 'html[lang=pt-BR]'
      assert_select 'main#main'
    end
    e = entry
    [entry_path(e), edit_entry_path(e), edit_category_path(@category)].each do |path|
      get path
      assert_response :success
    end
  end
  test 'crud e filtros de lançamento' do
    sign_in
    post entries_path, params: { entry: { date: '2026-11-10', description: 'Mercado sintético', category_id: @category.id, amount: '1.234,56', kind: 'expense', status: 'planned' }, installments: 1 }
    e = Entry.last
    assert_equal BigDecimal('1234.56'), e.amount
    follow_redirect!; assert_response :success
    patch entry_path(e), params: { entry: { date: '2026-11-10', description: 'Mercado sintético', category_id: @category.id, amount: '100,00', kind: 'expense', status: 'actual' } }
    assert_equal 'actual', e.reload.status
    get entries_path, params: { q: 'Mercado', month: 11, kind: 'expense', status: 'actual', category_id: @category.id }
    assert_select 'a.entry-title', text: 'Mercado sintético'
    get entries_path, params: { status: 'planned' }
    assert_select 'a.entry-title', count: 0
    delete entry_path(e)
    assert_not Entry.exists?(e.id)
  end
  test 'formulário inválido renderiza erros' do
    sign_in
    post entries_path, params: { entry: { date: '2026-11-10', description: '', category_id: @category.id, amount: '0', kind: 'expense', status: 'planned' } }
    assert_response :unprocessable_entity
    assert_select '[role=alert]'
  end
  test 'importação pode ser cancelada sem mudar dados' do
    sign_in
    original = entry
    file = workbook
    post import_path, params: { year: 2026, file: Rack::Test::UploadedFile.new(file.path, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }
    assert_redirected_to import_path
    follow_redirect!; assert_response :success
    assert_equal 1, Preview.count
    delete import_path
    assert_equal [original.id], Entry.pluck(:id)
    assert_equal 0, Preview.count
  ensure
    file&.close!
  end
  test 'confirmação da importação confere totais e consome prévia' do
    sign_in
    file = workbook
    post import_path, params: { year: 2026, file: Rack::Test::UploadedFile.new(file.path, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }
    post commit_import_path, params: { reviewed: '1' }
    assert_redirected_to root_path(year: 2026)
    assert_equal 6, Entry.count
    assert_equal 0, Preview.count
  ensure
    file&.close!
  end
  test 'logout bloqueia acesso posterior' do
    sign_in
    delete session_path
    get root_path
    assert_redirected_to new_session_path
  end
  test 'backup download e cancelamento da restauração' do
    sign_in
    entry
    get backup_path
    assert_response :success
    assert_equal 1, JSON.parse(response.body)['version']
    file = Tempfile.new(['backup', '.json']); file.write(response.body); file.flush
    post backup_path, params: { file: Rack::Test::UploadedFile.new(file.path, 'application/json') }
    assert_response :success
    delete cancel_backup_path
    assert_equal 1, Entry.count
    assert_equal 0, Preview.count
  ensure
    file&.close!
  end
  test 'reaproveitamento explícito do calendário aparece na prévia' do
    sign_in
    get new_import_path
    assert_select 'input[type=checkbox][name=force_year]'
    file = workbook(year: 2026)
    post import_path, params: { year: 2027, force_year: '1', file: Rack::Test::UploadedFile.new(file.path, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }
    assert_redirected_to import_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, 'Datas com ano ajustado: 1'
    assert_includes response.body, 'O ano informado foi escolhido explicitamente'
    data = @user.previews.sole.payload
    assert_equal 2027, data['year']
    assert data['entries'].all? { |entry| entry['date'].start_with?('2027-') }
    assert_equal 0, Entry.count
  ensure
    file&.close!
  end

end

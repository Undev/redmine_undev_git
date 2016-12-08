require File.expand_path('../../test_helper', __FILE__)

class RepositoriesUndevGitControllerTest < ActionController::TestCase
  tests RepositoriesController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
    :repositories, :enabled_modules

  REPOSITORY_PATH.gsub!(/\//, "\\") if Redmine::Platform.mswin?
  PRJ_ID         = 3
  CHAR_1_HEX     = "\xc3\x9c"
  NUM_REV        = 28

  ## Git, Mercurial and CVS path encodings are binary.
  ## Subversion supports URL encoding for path.
  ## Redmine Mercurial adapter and extension use URL encoding.
  ## Git accepts only binary path in command line parameter.
  ## So, there is no way to use binary command line parameter in JRuby.
  JRUBY_SKIP     = (RUBY_PLATFORM == 'java')
  JRUBY_SKIP_STR = 'TODO: This test fails in JRuby'

  def setup
    @ruby19_non_utf8_pass =
      (RUBY_VERSION >= '1.9' && Encoding.default_external.to_s != 'UTF-8')

    make_temp_dir
    Setting.enabled_scm << 'UndevGit'

    User.current = nil
    @project     = Project.find(PRJ_ID)
    @repository  = create_test_repository(
      project:       @project,
      url:           REPOSITORY_PATH,
      path_encoding: 'ISO-8859-1'
    )
    assert @repository
    @char_1 = CHAR_1_HEX.dup
    if @char_1.respond_to?(:force_encoding)
      @char_1.force_encoding('UTF-8')
    end
  end

  if File.directory?(REPOSITORY_PATH)
    ## Ruby uses ANSI api to fork a process on Windows.
    ## Japanese Shift_JIS and Traditional Chinese Big5 have 0x5c(backslash) problem
    ## and these are incompatible with ASCII.
    ## Git for Windows (msysGit) changed internal API from ANSI to Unicode in 1.7.10
    ## http://code.google.com/p/msysgit/issues/detail?id=80
    ## So, Latin-1 path tests fail on Japanese Windows
    WINDOWS_PASS     = (Redmine::Platform.mswin? &&
      Redmine::Scm::Adapters::UndevGitAdapter.client_version_above?([1, 7, 10]))
    WINDOWS_SKIP_STR = 'TODO: This test fails in Git for Windows above 1.7.10'

    def test_create_and_update
      @request.session[:user_id] = 1
      @project.repository.update_attribute(:url, 'none')
      assert_difference 'Repository.count' do
        post :create, project_id: 'subproject1',
          repository_scm:         'UndevGit',
          repository:             {
            url:                      REPOSITORY_PATH,
            is_default:               '0',
            identifier:               'test-create',
            extra_report_last_commit: '1',
            use_init_hooks:           '1'
          }
      end
      assert_response 302
      repository = Repository.last
      assert_kind_of Repository::UndevGit, repository
      assert_equal REPOSITORY_PATH, repository.url
      assert repository.extra_report_last_commit
      assert repository.use_init_hooks?

      put :update, id: repository.id,
        repository:    {
          extra_report_last_commit: '0'
        }
      assert_response 302
      repo2 = Repository.find(repository.id)
      refute repo2.extra_report_last_commit
    end

    def test_get_new
      @request.session[:user_id] = 1
      @project.repository.destroy
      get :new, project_id: 'subproject1', repository_scm: 'UndevGit'
      assert_response :success
      assert_template 'new'
      assert_kind_of Repository::UndevGit, assigns(:repository)
      assert assigns(:repository).new_record?
    end

    def test_browse_root
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count

      get :show, id: PRJ_ID
      assert_response :success
      assert_template 'show'
      assert_not_nil assigns(:entries)
      assert_equal 9, assigns(:entries).size
      assert assigns(:entries).detect { |e| e.name == 'images' && e.kind == 'dir' }
      assert assigns(:entries).detect { |e| e.name == 'this_is_a_really_long_and_verbose_directory_name' && e.kind == 'dir' }
      assert assigns(:entries).detect { |e| e.name == 'sources' && e.kind == 'dir' }
      assert assigns(:entries).detect { |e| e.name == 'README' && e.kind == 'file' }
      assert assigns(:entries).detect { |e| e.name == 'copied_README' && e.kind == 'file' }
      assert assigns(:entries).detect { |e| e.name == 'new_file.txt' && e.kind == 'file' }
      assert assigns(:entries).detect { |e| e.name == 'renamed_test.txt' && e.kind == 'file' }
      assert assigns(:entries).detect { |e| e.name == 'filemane with spaces.txt' && e.kind == 'file' }
      assert assigns(:entries).detect { |e| e.name == ' filename with a leading space.txt ' && e.kind == 'file' }
      assert_not_nil assigns(:changesets)
      assert assigns(:changesets).size > 0
    end

    def test_browse_branch
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      get :show, id: PRJ_ID, rev: 'test_branch'
      assert_response :success
      assert_template 'show'
      assert_not_nil assigns(:entries)
      assert_equal 4, assigns(:entries).size
      assert assigns(:entries).detect { |e| e.name == 'images' && e.kind == 'dir' }
      assert assigns(:entries).detect { |e| e.name == 'sources' && e.kind == 'dir' }
      assert assigns(:entries).detect { |e| e.name == 'README' && e.kind == 'file' }
      assert assigns(:entries).detect { |e| e.name == 'test.txt' && e.kind == 'file' }
      assert_not_nil assigns(:changesets)
      assert assigns(:changesets).size > 0
    end

    def test_browse_tag
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      [
        'tag00.lightweight',
        'tag01.annotated',
      ].each do |t1|
        get :show, id: PRJ_ID, rev: t1
        assert_response :success
        assert_template 'show'
        assert_not_nil assigns(:entries)
        assert assigns(:entries).size > 0
        assert_not_nil assigns(:changesets)
        assert assigns(:changesets).size > 0
      end
    end

    def test_browse_directory
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      get :show, id: PRJ_ID, path: repository_path_hash(['images'])[:param]
      assert_response :success
      assert_template 'show'
      assert_not_nil assigns(:entries)
      assert_equal ['edit.png'], assigns(:entries).collect(&:name)
      entry = assigns(:entries).detect { |e| e.name == 'edit.png' }
      assert_not_nil entry
      assert_equal 'file', entry.kind
      assert_equal 'images/edit.png', entry.path
      assert_not_nil assigns(:changesets)
      assert assigns(:changesets).size > 0
    end

    def test_browse_at_given_revision
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      get :show, id: PRJ_ID, path: repository_path_hash(['images'])[:param],
        rev:         '7234cb2750b63f47bff735edc50a1c0a433c2518'
      assert_response :success
      assert_template 'show'
      assert_not_nil assigns(:entries)
      assert_equal ['delete.png'], assigns(:entries).collect(&:name)
      assert_not_nil assigns(:changesets)
      assert assigns(:changesets).size > 0
    end

    def test_changes
      @repository.fetch_changesets
      get :changes, id: PRJ_ID,
        path:           repository_path_hash(['images', 'edit.png'])[:param]
      assert_response :success
      assert_template 'changes'
      assert_select 'h2', 'edit.png'
    end

    def test_entry_show
      @repository.fetch_changesets
      get :entry, id: PRJ_ID,
        path:         repository_path_hash(['sources', 'watchers_controller.rb'])[:param]
      assert_response :success
      assert_template 'entry'
      # Line 19
      assert_tag tag: 'th',
        content:      '11',
        attributes:   { class: 'line-num' },
        sibling:      { tag: 'td', content: /WITHOUT ANY WARRANTY/ }
    end

    def test_entry_show_latin_1
      @repository.fetch_changesets
      if @ruby19_non_utf8_pass
        puts_ruby19_non_utf8_pass()
      elsif WINDOWS_PASS
        puts WINDOWS_SKIP_STR
      elsif JRUBY_SKIP
        puts JRUBY_SKIP_STR
      else
        with_settings repositories_encodings: 'UTF-8,ISO-8859-1' do
          ['57ca437c', '57ca437c0acbbcb749821fdf3726a1367056d364'].each do |r1|
            get :entry, id: PRJ_ID,
              path:         repository_path_hash(['latin-1-dir', "test-#{@char_1}.txt"])[:param],
              rev:          r1
            assert_response :success
            assert_template 'entry'
            assert_select 'th.line-num', '1'
            assert_select 'th.line-num ~ td', /test-#{@char_1}.txt/
          end
        end
      end
    end

    def test_entry_download
      @repository.fetch_changesets
      get :entry, id: PRJ_ID,
        path:         repository_path_hash(['sources', 'watchers_controller.rb'])[:param],
        format:       'raw'
      assert_response :success
      # File content
      assert @response.body.include?('WITHOUT ANY WARRANTY')
    end

    def test_directory_entry
      @repository.fetch_changesets
      get :entry, id: PRJ_ID,
        path:         repository_path_hash(['sources'])[:param]
      assert_response :success
      assert_template 'show'
      assert_not_nil assigns(:entry)
      assert_equal 'sources', assigns(:entry).name
    end

    def test_diff
      assert @repository.is_default
      assert_nil @repository.identifier
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      # Full diff of changeset 2f9c0091
      ['inline', 'sbs'].each do |dt|
        get :diff,
          id:   PRJ_ID,
          rev:  '2f9c0091c754a91af7a9c478e36556b4bde8dcf7',
          type: dt
        assert_response :success
        assert_template 'diff'
        # Line 22 removed
        assert_select 'th', /22/
        assert_select 'th', /2f9c0091/
        assert_select 'th ~ td.diff_out', /def remove/
        assert_tag tag: 'th',
          content:      /22/,
          sibling:      { tag: 'td',
            attributes:        { class: /diff_out/ },
            content:           /def remove/ }
        assert_tag tag: 'h2', content: /2f9c0091/
      end
    end

    def test_diff_with_rev_and_path
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      with_settings diff_max_lines_displayed: 1000 do
        # Full diff of changeset 2f9c0091
        ['inline', 'sbs'].each do |dt|
          get :diff,
            id:   PRJ_ID,
            rev:  '2f9c0091c754a91af7a9c478e36556b4bde8dcf7',
            path: repository_path_hash(['sources', 'watchers_controller.rb'])[:param],
            type: dt
          assert_response :success
          assert_template 'diff'
          # Line 22 removed
          assert_tag tag: 'th',
            content:      '22',
            sibling:      { tag: 'td',
              attributes:        { class: /diff_out/ },
              content:           /def remove/ }
          assert_tag tag: 'h2', content: /2f9c0091/
        end
      end
    end

    def test_diff_truncated
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count

      with_settings diff_max_lines_displayed: 5 do
        # Truncated diff of changeset 2f9c0091
        with_cache do
          with_settings default_language: 'en' do
            get :diff, id: PRJ_ID, type: 'inline',
              rev:         '2f9c0091c754a91af7a9c478e36556b4bde8dcf7'
            assert_response :success
            assert @response.body.include?('... This diff was truncated')
          end
          with_settings default_language: 'fr' do
            get :diff, id: PRJ_ID, type: 'inline',
              rev:         '2f9c0091c754a91af7a9c478e36556b4bde8dcf7'
            assert_response :success
            assert !@response.body.include?('... This diff was truncated')
            assert @response.body.include?('... Ce diff')
          end
        end
      end
    end

    def test_diff_two_revs
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      ['inline', 'sbs'].each do |dt|
        get :diff,
          id:     PRJ_ID,
          rev:    '61b685fbe55ab05b5ac68402d5720c1a6ac973d1',
          rev_to: '2f9c0091c754a91af7a9c478e36556b4bde8dcf7',
          type:   dt
        assert_response :success
        assert_template 'diff'
        diff = assigns(:diff)
        assert_not_nil diff
        assert_tag tag: 'h2', content: /2f9c0091c:61b685fbe/
        assert_tag tag: 'form',
          attributes:   {
            action: '/projects/subproject1/repository/revisions/' +
                      '61b685fbe55ab05b5ac68402d5720c1a6ac973d1/diff'
          }
        assert_tag tag: 'input',
          attributes:   {
            id:    'rev_to',
            name:  'rev_to',
            type:  'hidden',
            value: '2f9c0091c754a91af7a9c478e36556b4bde8dcf7'
          }
      end
    end

    def test_diff_path_in_subrepo
      @repository.fetch_changesets
      @project.repository.update_attribute(:url, 'none')
      repo = Repository::UndevGit.create(
        project:       @project,
        url:           REPOSITORY_PATH,
        identifier:    'test-diff-path',
        path_encoding: 'ISO-8859-1'
      )
      repo.fetch_changesets
      assert repo
      refute repo.is_default
      assert_equal 'test-diff-path', repo.identifier
      get :diff,
        id:            PRJ_ID,
        repository_id: 'test-diff-path',
        rev:           '61b685fbe55ab05b',
        rev_to:        '2f9c0091c754a91a',
        type:          'inline'
      assert_response :success
      assert_template 'diff'
      diff = assigns(:diff)
      assert_not_nil diff
      assert_tag tag: 'form',
        attributes:   {
          action: '/projects/subproject1/repository/test-diff-path/' +
                    'revisions/61b685fbe55ab05b/diff'
        }
      assert_tag tag: 'input',
        attributes:   {
          id:    'rev_to',
          name:  'rev_to',
          type:  'hidden',
          value: '2f9c0091c754a91a'
        }
    end

    def test_diff_latin_1
      @repository.fetch_changesets
      if @ruby19_non_utf8_pass
        puts_ruby19_non_utf8_pass()
      else
        with_settings repositories_encodings: 'UTF-8,ISO-8859-1' do
          ['57ca437c', '57ca437c0acbbcb749821fdf3726a1367056d364'].each do |r1|
            ['inline', 'sbs'].each do |dt|
              get :diff, id: PRJ_ID, rev: r1, type: dt
              assert_response :success
              assert_template 'diff'
              assert_tag tag: 'thead',
                descendant:   {
                  tag:        'th',
                  attributes: { class: 'filename' },
                  content:    /latin-1-dir\/test-#{@char_1}.txt/,
                },
                sibling:      {
                  tag:        'tbody',
                  descendant: {
                    tag:        'td',
                    attributes: { class: /diff_in/ },
                    content:    /test-#{@char_1}.txt/
                  }
                }
            end
          end
        end
      end
    end

    def test_diff_should_show_filenames
      @repository.fetch_changesets
      get :diff, id: PRJ_ID, rev: 'deff712f05a90d96edbd70facc47d944be5897e3', type: 'inline'
      assert_response :success
      assert_template 'diff'
      # modified file
      assert_select 'th.filename', text: /sources\/watchers_controller\.rb/
      # deleted file
      assert_select 'th.filename', text: /test\.txt/
    end

    def test_save_diff_type
      @repository.fetch_changesets
      user1                  = User.find(1)
      user1.pref[:diff_type] = nil
      user1.preference.save
      user = User.find(1)
      assert_nil user.pref[:diff_type]

      @request.session[:user_id] = 1 # admin
      get :diff,
        id:  PRJ_ID,
        rev: '2f9c0091c754a91af7a9c478e36556b4bde8dcf7'
      assert_response :success
      assert_template 'diff'
      user.reload
      assert_equal 'inline', user.pref[:diff_type]
      get :diff,
        id:   PRJ_ID,
        rev:  '2f9c0091c754a91af7a9c478e36556b4bde8dcf7',
        type: 'sbs'
      assert_response :success
      assert_template 'diff'
      user.reload
      assert_equal 'sbs', user.pref[:diff_type]
    end

    def test_annotate
      @repository.fetch_changesets
      get :annotate, id: PRJ_ID,
        path:            repository_path_hash(['sources', 'watchers_controller.rb'])[:param]
      assert_response :success
      assert_template 'annotate'

      # Line 23, changeset 2f9c0091
      assert_select 'tr' do
        assert_select 'th.line-num', text: '23'
        assert_select 'td.revision', text: /2f9c0091/
        assert_select 'td.author', text: 'jsmith'
        assert_select 'td', text: /remove_watcher/
      end
    end

    def test_annotate_at_given_revision
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      get :annotate, id: PRJ_ID, rev: 'deff7',
        path:            repository_path_hash(['sources', 'watchers_controller.rb'])[:param]
      assert_response :success
      assert_template 'annotate'
      assert_tag tag: 'h2', content: /@ deff712f/
    end

    def test_annotate_binary_file
      @repository.fetch_changesets
      get :annotate, id: PRJ_ID,
        path:            repository_path_hash(['images', 'edit.png'])[:param]
      assert_response 500
      assert_tag tag: 'p', attributes: { id: /errorExplanation/ },
        content:      /cannot be annotated/
    end

    def test_annotate_error_when_too_big
      @repository.fetch_changesets
      with_settings file_max_size_displayed: 1 do
        get :annotate, id: PRJ_ID,
          path:            repository_path_hash(['sources', 'watchers_controller.rb'])[:param],
          rev:             'deff712f'
        assert_response 500
        assert_tag tag: 'p', attributes: { id: /errorExplanation/ },
          content:      /exceeds the maximum text file size/

        get :annotate, id: PRJ_ID,
          path:            repository_path_hash(['README'])[:param],
          rev:             '7234cb2'
        assert_response :success
        assert_template 'annotate'
      end
    end

    def test_annotate_latin_1
      @repository.fetch_changesets
      if @ruby19_non_utf8_pass
        puts_ruby19_non_utf8_pass()
      elsif WINDOWS_PASS
        puts WINDOWS_SKIP_STR
      elsif JRUBY_SKIP
        puts JRUBY_SKIP_STR
      else
        with_settings repositories_encodings: 'UTF-8,ISO-8859-1' do
          ['57ca437c', '57ca437c0acbbcb749821fdf3726a1367056d364'].each do |r1|
            get :annotate, id: PRJ_ID,
              path:            repository_path_hash(['latin-1-dir', "test-#{@char_1}.txt"])[:param],
              rev:             r1
            assert_tag tag: 'th',
              content:      '1',
              attributes:   { class: 'line-num' },
              sibling:      { tag: 'td',
                content:           /test-#{@char_1}.txt/ }
          end
        end
      end
    end

    def test_revisions
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      get :revisions, id: PRJ_ID
      assert_response :success
      assert_template 'revisions'
      assert_tag tag: 'form',
        attributes:   {
          method: 'get',
          action: '/projects/subproject1/repository/revision'
        }
    end

    def test_revision
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      ['61b685fbe55ab05b5ac68402d5720c1a6ac973d1', '61b685f'].each do |r|
        get :revision, id: PRJ_ID, rev: r
        assert_response :success
        assert_template 'revision'
      end
    end

    def test_empty_revision
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count
      ['', ' ', nil].each do |r|
        get :revision, id: PRJ_ID, rev: r
        assert_response 404
      end
    end

    def test_destroy_valid_repository
      @request.session[:user_id] = 1 # admin
      assert_equal 0, @repository.changesets.count
      @repository.fetch_changesets
      @project.reload
      assert_equal NUM_REV, @repository.changesets.count

      assert_difference 'Repository.count', -1 do
        delete :destroy, id: @repository.id
      end
      assert_response 302
      @project.reload
      assert_nil @project.repository
    end

    def test_destroy_repository
      @request.session[:user_id] = 1 # admin
      @project.repository.destroy
      @repository = Repository::UndevGit.create!(
        project:       @project,
        url:           REPOSITORY_PATH,
        path_encoding: 'ISO-8859-1'
      )
      @repository.reload
      assert_equal 0, @repository.changesets.count

      assert_difference 'Repository.count', -1 do
        delete :destroy, id: @repository.id
      end
      assert_response 302
      @project.reload
      assert_nil @project.repository
    end

    def test_branches_in_commit_view
      @repository.fetch_changesets
      changeset    = @repository.changesets.last
      max_branches = 15
      branches     = Array.new(max_branches) { |i| "fakebranch#{i}" }
      changeset.update_attribute :branches, branches

      get :revision, id: PRJ_ID, rev: changeset.revision
      assert_response :success

      assert_select 'table.revision-info a', { text: /fakebranch/ } do |links|
        assert_equal max_branches, links.length
      end
    end

    def test_new_form_contains_fetch_by_web_hook_checkbox
      @request.session[:user_id] = 1
      get :new, project_id: 'subproject1', repository_scm: 'UndevGit'
      assert_response :success
      assert_select 'input#repository_fetch_by_web_hook'
    end

    def test_create_with_fetch_by_web_hook
      @request.session[:user_id] = 1
      repo_url                   = 'https://github.com/Restream/redmine_undev_git.git'
      post :create,
        project_id:     'subproject1',
        repository_scm: 'UndevGit',
        repository:     {
          url:               repo_url,
          is_default:        '0',
          identifier:        'test-create-wbh',
          fetch_by_web_hook: '1'
        }
      assert_response 302
      repository = Repository::UndevGit.find_by_url repo_url
      assert repository
      assert repository.fetch_by_web_hook?

      put :update, id: repository.id,
        repository:    {
          fetch_by_web_hook: '0'
        }
      assert_response 302
      repository = Repository::UndevGit.find_by_url repo_url
      refute repository.fetch_by_web_hook?
    end

    private

    def puts_ruby19_non_utf8_pass
      puts 'TODO: This test fails in Ruby 1.9 ' +
        'and Encoding.default_external is not UTF-8. ' +
        "Current value is '#{Encoding.default_external.to_s}'"
    end
  else
    puts 'Git test repository NOT FOUND. Skipping functional tests !!!'

    def test_fake;
      assert true
    end
  end

  private
  def with_cache(&block)
    before                                 = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true
    block.call
    ActionController::Base.perform_caching = before
  end
end

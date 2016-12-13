require_dependency 'time_entry'

module RedmineUndevGit
  module Patches
    module TimeEntryPatch

      def self.prepended(base)
        base.class_eval do

          belongs_to :remote_repo_revision

        end
      end

    end
  end
end

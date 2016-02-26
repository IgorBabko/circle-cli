require 'gitable'
require 'rugged'

module Circle
  module CLI
    class Repo
      attr_reader :repo, :origin, :uri, :errors, :options

      def initialize(options = {})
        @options = options
        @errors = []
      end

      def uri
        Gitable::URI.parse(origin.url)
      end

      def valid?
        errors.clear
        errors << "Unsupported repo url format #{uri}" unless uri.github?
        errors << "Couldn't locate branch" if options[:branch] && !branch
        errors << no_github_token_message unless github_token

        # The following validation is temporarily disabled
        # errors << no_circle_token_message unless circle_token

        errors.empty?
      end

      def github
        uri.path.gsub(/\.git$/, '') if uri.github?
      end

      def target
        if branch
          branch.target_id
        else
          repo.head.target_id
        end
      end

      def github_token
        repo.config['github.token']
      end

      def github_token=(token)
        repo.config['github.token'] = token
      end

      def circle_token
        repo.config['circleci.token']
      end

      def circle_token=(token)
        repo.config['circleci.token'] = token
      end

      def no_github_token_message
        no_token_message 'Github', 'https://github.com/settings/tokens/new', 'github'
      end

      def no_circle_token_message
        no_token_message 'CircleCI', 'https://circleci.com/account/api', 'ci'
      end

      private

      def repo
        @repo ||= Rugged::Repository.new(options[:repo])
      end

      def branch
        @branch ||= repo.branches[options[:branch]] if options[:branch]
      end

      def origin
        @origin ||= repo.remotes.find { |r| r.name == 'origin' }
      end

      def no_token_message(provider, url, command)
        <<-EOMSG
#{provider} token hasn't been configured. You can create one here:

  #{url}

Once you have a token, add it with the following command:

  $ circle token #{command} YOUR_TOKEN
        EOMSG
      end
    end
  end
end

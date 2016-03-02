require 'launchy'
require 'circle/cli/repo'
require 'circle/cli/project'

module Circle
  module CLI
    class App < Thor
      CIRCLE_URL = 'https://circleci.com/account/api'

      STATUS_COLORS = {
        green: %w(fixed success),
        yellow: %w(running retried not_run queued scheduled not_running no_tests),
        red: %w(canceled infrastructure_fail timedout failed)
      }

      LOGIN_HELP = <<-EOMSG
1. Press [enter], and you'll be taken CircleCI.
2. Enter a name for your new token.
3. Click 'Create new token'.
4. Come back to your prompt and paste in your new token.
5. Press enter to complete the process.
      EOMSG

      NO_TOKEN_MESSAGE = <<-EOMSG
CircleCI token hasn't been configured. Run the following command to login:

  $ circle login
      EOMSG

      default_task :status
      class_option :repo, default: '.', desc: 'path to repo'

      desc 'status', 'show CircleCI build result'
      method_option :branch, desc: 'branch name'
      def status
        validate_repo!
        validate_latest!
        display_status
      end

      desc 'watch', 'watch your build'
      method_option :branch, desc: 'branch name'
      method_option :poll, default: 5, desc: 'polling frequency', type: :numeric
      def watch
        validate_repo!
        validate_latest!

        loop do
          display_status
          sleep options[:poll]
          project.rebuild_latest_cache
          system('clear') || system('cls')
        end
      end

      desc 'overview', 'list recent builds and their statuses for all branches'
      def overview
        validate_repo!
        abort! 'No recent builds.' if project.recent_builds.empty?
        print_table builds_to_rows(project.recent_builds)
      end

      desc 'open', 'open CircleCI build'
      method_option :branch, desc: 'branch name'
      def open
        validate_repo!
        validate_latest!
        Launchy.open project['build_url']
      end

      desc 'build', 'trigger a build on circle ci'
      method_option :branch, desc: 'branch name'
      def build
        validate_repo!
        project.build!
        say "A build has been triggered.\n\n", :green
        invoke :watch
      end

      desc 'cancel', 'cancel most recent build'
      method_option :branch, desc: 'branch name'
      def cancel
        validate_repo!
        validate_latest!

        project.cancel! unless project['outcome']
        invoke :status
        say "\nThe build has been cancelled.", :red unless project['outcome']
      end

      desc 'token', 'view or edit CircleCI token'
      def token(value = nil)
        if value
          repo.circle_token = value
        elsif value = repo.circle_token
          say value
        else
          say NO_TOKEN_MESSAGE, :yellow
        end
      end

      desc 'login', 'login to Circle CI'
      def login
        say LOGIN_HELP, :yellow
        ask set_color("\nPress [enter] to open CircleCI", :blue)
        Launchy.open(CIRCLE_URL)
        value = ask set_color('Enter your token:', :blue)
        repo.circle_token = value
        say "\nYour token has been set to '#{value}'.", :green
      end

      private

      def repo
        @repo ||= Repo.new(options)
      end

      def project
        @project ||= Project.new(repo)
      end

      def validate_repo!
        abort! "Unsupported repo url format #{repo.uri}" unless repo.uri.github?
        abort! NO_TOKEN_MESSAGE unless repo.circle_token
      end

      def validate_latest!
        abort! 'No CircleCI builds found.' unless project.latest
      end

      def display_status
        start_time = pretty_date(project['start_time']) || 'Not started'
        stop_time = pretty_date(project['stop_time']) || 'Not finished'

        say "#{project['subject']}\n\n", :cyan if project['subject']
        color = color_for_status project['status']
        say_project 'Build status', project['status'].capitalize, color
        say_project 'Started at', start_time, color
        say_project 'Finished at', stop_time, color
        say_project 'Compare', project['compare'], color if project['compare']
        display_steps project.latest_details['steps']

        failures = project.latest_test_results.failing
        display_failures failures unless failures.empty?
        exit_for_appropriate_outcome project['outcome']
      end

      def abort!(message)
        abort set_color(message, :red)
      end

      def exit_for_appropriate_outcome(outcome)
        if outcome && outcome == 'failed'
          exit 1
        elsif outcome
          exit 0
        end
      end

      def color_for_status(status)
        case status
        when *STATUS_COLORS[:green] then :green
        when *STATUS_COLORS[:yellow] then :yellow
        when *STATUS_COLORS[:red] then :red
        else :blue
        end
      end

      def builds_to_rows(builds)
        builds.map do |build|
          branch = set_color(build['branch'], :bold)
          status_color = color_for_status(build['status'])
          status = build['status'].tr('_', ' ').capitalize
          status = set_color(status, status_color)
          subject = truncate build['subject']
          started = pretty_date(build['start_time'])
          [branch, status, subject, started]
        end
      end

      def display_steps(steps)
        return if steps.empty?
        say "\nSteps:", :bold

        print_table steps.map { |step|
          action = step['actions'].first
          color = color_for_status action['status']
          millis = action['run_time_millis']
          runtime = human_duration(millis) if millis
          [set_color(step['name'], color), runtime]
        }
      end

      def say_project(description, value, color)
        status = set_color description.ljust(15), :bold
        result = set_color value.to_s, color
        say "#{status} #{result}"
      end

      def display_failures(failures)
        say "\nFailing specs:", :bold

        print_table failures.map { |spec|
          [set_color(spec['file'], :red), spec['name']]
        }
      end

      def truncate(str, length = 50)
        return str if !str || str.length <= length
        "#{str[0..50]}..."
      end

      def pretty_date(str)
        Time.parse(str).strftime('%b %e, %-l:%M %p') if str
      rescue ArgumentError
      end

      def human_duration(ms)
        hours = (ms / (1000 * 60 * 60)) % 24
        minutes = (ms / (1000 * 60)) % 60
        seconds = (ms / 1000) % 60

        message = []
        message << "#{hours}h" unless hours.zero?
        message << "#{minutes}m" unless minutes.zero?
        message << "#{seconds}s" unless seconds.zero?
        message << "#{ms}ms" if message.empty?
        message.join(' ')
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java_script/npm_and_yarn/version_resolver"

namespace = Dependabot::UpdateCheckers::JavaScript::NpmAndYarn
RSpec.describe namespace::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      latest_allowable_version: latest_allowable_version,
      latest_version_finder: latest_version_finder
    )
  end
  let(:latest_version_finder) do
    namespace::LatestVersionFinder.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: []
    )
  end
  let(:react_dom_registry_listing_url) do
    "https://registry.npmjs.org/react-dom"
  end
  let(:react_dom_registry_response) do
    fixture("javascript", "npm_responses", "react-dom.json")
  end
  let(:react_registry_listing_url) { "https://registry.npmjs.org/react" }
  let(:react_registry_response) do
    fixture("javascript", "npm_responses", "react.json")
  end
  before do
    stub_request(:get, react_dom_registry_listing_url).
      to_return(status: 200, body: react_dom_registry_response)
    stub_request(:get, react_dom_registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
    stub_request(:get, react_registry_listing_url).
      to_return(status: 200, body: react_registry_response)
    stub_request(:get, react_registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
  end

  let(:dependency_files) { [package_json] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("javascript", "package_files", manifest_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("javascript", "yarn_lockfiles", yarn_lock_fixture_name)
    )
  end
  let(:yarn_lock_fixture_name) { "yarn.lock" }
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("javascript", "npm_lockfiles", npm_lock_fixture_name)
    )
  end
  let(:npm_lock_fixture_name) { "package-lock.json" }
  let(:shrinkwrap) do
    Dependabot::DependencyFile.new(
      name: "npm-shrinkwrap.json",
      content: fixture("javascript", "npm_lockfiles", shrinkwrap_fixture_name)
    )
  end
  let(:shrinkwrap_fixture_name) { "package-lock.json" }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  describe "#latest_resolvable_version" do
    subject { resolver.latest_resolvable_version }

    context "with a package-lock.json" do
      let(:dependency_files) { [package_json, npm_lock] }

      context "updating a dependency without peer dependency issues" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "package-lock.json" }
        let(:latest_allowable_version) { Gem::Version.new("1.0.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.0.0",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }

        context "that is a git dependency" do
          let(:manifest_fixture_name) { "git_dependency.json" }
          let(:npm_lock_fixture_name) { "git_dependency.json" }
          let(:latest_allowable_version) do
            "0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "is-number",
              version: "af885e2e890b9ef0875edd2b117305119ee5bdc5",
              requirements: [{
                requirement: nil,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/jonschlinkert/is-number",
                  branch: nil,
                  ref: "master"
                }
              }],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency with a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:npm_lock_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }

        context "that has (old) peer requirements that aren't included" do
          let(:manifest_fixture_name) { "peer_dependency_changed.json" }
          let(:npm_lock_fixture_name) { "peer_dependency_changed.json" }
          let(:latest_allowable_version) { Gem::Version.new("2.2.4") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react-apollo",
              version: "2.1.8",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "^2.1.8",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end

          let(:react_apollo_registry_listing_url) do
            "https://registry.npmjs.org/react-apollo"
          end
          let(:react_apollo_registry_response) do
            fixture("javascript", "npm_responses", "react-apollo.json")
          end
          before do
            stub_request(:get, react_apollo_registry_listing_url).
              to_return(status: 200, body: react_apollo_registry_response)
            stub_request(:get, react_apollo_registry_listing_url + "/latest").
              to_return(status: 200, body: "{}")
          end

          # Upgrading react-apollo is blocked by our apollo-client version.
          # This test also checks that the old peer requirement on redux, which
          # is no longer in the package.json, doesn't cause any problems *and*
          # tests that complicated react peer requirements are processed OK.
          it { is_expected.to eq(Gem::Version.new("2.1.9")) }
        end

        context "that previously had the peer dependency as a normal dep" do
          let(:manifest_fixture_name) { "peer_dependency_switch.json" }
          let(:npm_lock_fixture_name) { "peer_dependency_switch.json" }
          let(:latest_allowable_version) { Gem::Version.new("2.5.4") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react-burger-menu",
              version: "1.8.4",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "~1.8.0",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end

          let(:react_burger_menu_registry_listing_url) do
            "https://registry.npmjs.org/react-burger-menu"
          end
          let(:react_burger_menu_registry_response) do
            fixture("javascript", "npm_responses", "react-burger-menu.json")
          end
          before do
            stub_request(:get, react_burger_menu_registry_listing_url).
              to_return(status: 200, body: react_burger_menu_registry_response)
            stub_request(
              :get,
              react_burger_menu_registry_listing_url + "/latest"
            ).to_return(status: 200, body: "{}")
          end

          it { is_expected.to eq(Gem::Version.new("1.9.0")) }
        end
      end

      context "updating a dependency that is a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:npm_lock_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }

        context "of multiple dependencies" do
          let(:manifest_fixture_name) { "peer_dependency_multiple.json" }
          let(:npm_lock_fixture_name) { "peer_dependency_multiple.json" }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react",
              version: "0.14.2",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "0.14.2",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("0.14.9")) }
        end
      end
    end

    context "with a npm-shrinkwrap.json" do
      let(:dependency_files) { [package_json, shrinkwrap] }

      # Shrinkwrap case is mainly covered by package-lock.json specs (since
      # resolution is identical). Single spec ensures things are working
      context "updating a dependency with a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:shrinkwrap_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }
      end
    end

    context "with no lockfile" do
      let(:dependency_files) { [package_json] }

      context "updating a dependency without peer dependency issues" do
        let(:manifest_fixture_name) { "package.json" }
        let(:latest_allowable_version) { Gem::Version.new("1.0.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }

        context "that is a git dependency" do
          let(:manifest_fixture_name) { "git_dependency.json" }
          let(:latest_allowable_version) do
            "0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "is-number",
              version: nil,
              requirements: [{
                requirement: nil,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/jonschlinkert/is-number",
                  branch: nil,
                  ref: "master"
                }
              }],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency with a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-dom",
            version: nil,
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        # We don't handle updates without a lockfile properly yet
        it { is_expected.to eq(Gem::Version.new("15.2.0")) }

        context "to an acceptable version" do
          let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
          it { is_expected.to eq(Gem::Version.new("15.6.2")) }
        end

        context "that is a git dependency" do
          let(:manifest_fixture_name) { "peer_dependency_git.json" }
          let(:latest_allowable_version) do
            "1af607cc24ee57b338c18e1a67eae445da86b316"
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@trainline/react-skeletor",
              version: nil,
              requirements: [{
                requirement: nil,
                file: "package.json",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/trainline/react-skeletor",
                  branch: nil,
                  ref: "master"
                }
              }],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency that is a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: nil,
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }

        context "to an acceptable version" do
          let(:latest_allowable_version) { Gem::Version.new("15.6.2") }
          it { is_expected.to eq(Gem::Version.new("15.6.2")) }
        end
      end

      context "when there are already peer requirement issues" do
        let(:manifest_fixture_name) { "peer_dependency_mismatch.json" }

        context "for a dependency with issues" do
          let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react",
              version: nil,
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "^15.2.0",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("16.3.1")) }
        end

        context "updating an unrelated dependency" do
          let(:latest_allowable_version) { Gem::Version.new("0.2.1") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "fetch-factory",
              version: nil,
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "^0.0.1",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("0.2.1")) }

          context "with a dependency version that can't be found" do
            let(:manifest_fixture_name) { "yanked_version.json" }
            let(:latest_allowable_version) { Gem::Version.new("99.0.0") }
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "fetch-factory",
                version: nil,
                package_manager: "npm_and_yarn",
                requirements: [{
                  file: "package.json",
                  requirement: "^99.0.0",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end

            # We let the latest version through here, rather than raising.
            # Eventually error handling should be moved from the FileUpdater
            # to here
            it { is_expected.to eq(Gem::Version.new("99.0.0")) }
          end
        end
      end
    end

    context "with a yarn.lock" do
      let(:dependency_files) { [package_json, yarn_lock] }

      context "updating a dependency without peer dependency issues" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "yarn.lock" }
        let(:latest_allowable_version) { Gem::Version.new("1.0.0") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.0.0",
            requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(latest_allowable_version) }

        context "that is a git dependency" do
          let(:manifest_fixture_name) { "git_dependency.json" }
          let(:yarn_lock_fixture_name) { "git_dependency.lock" }
          let(:latest_allowable_version) do
            "0c6b15a88bc10cd47f67a09506399dfc9ddc075d"
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "is-number",
              version: "af885e2e890b9ef0875edd2b117305119ee5bdc5",
              requirements: [{
                requirement: nil,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/jonschlinkert/is-number",
                  branch: nil,
                  ref: "master"
                }
              }],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(latest_allowable_version) }
        end
      end

      context "updating a dependency with a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:yarn_lock_fixture_name) { "peer_dependency.lock" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.2.0")) }

        context "that previously had the peer dependency as a normal dep" do
          let(:manifest_fixture_name) { "peer_dependency_switch.json" }
          let(:yarn_lock_fixture_name) { "peer_dependency_switch.lock" }
          let(:latest_allowable_version) { Gem::Version.new("2.5.4") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react-burger-menu",
              version: "1.8.4",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "~1.8.0",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end

          let(:react_burger_menu_registry_listing_url) do
            "https://registry.npmjs.org/react-burger-menu"
          end
          let(:react_burger_menu_registry_response) do
            fixture("javascript", "npm_responses", "react-burger-menu.json")
          end
          before do
            stub_request(:get, react_burger_menu_registry_listing_url).
              to_return(status: 200, body: react_burger_menu_registry_response)
            stub_request(
              :get,
              react_burger_menu_registry_listing_url + "/latest"
            ).to_return(status: 200, body: "{}")
          end

          it { is_expected.to eq(Gem::Version.new("1.9.0")) }
        end
      end

      context "updating a dependency that is a peer requirement" do
        let(:manifest_fixture_name) { "peer_dependency.json" }
        let(:yarn_lock_fixture_name) { "peer_dependency.lock" }
        let(:latest_allowable_version) { Gem::Version.new("16.3.1") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "15.2.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^15.2.0",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        it { is_expected.to eq(Gem::Version.new("15.6.2")) }

        context "of multiple dependencies" do
          let(:manifest_fixture_name) { "peer_dependency_multiple.json" }
          let(:yarn_lock_fixture_name) { "peer_dependency_multiple.lock" }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "react",
              version: "0.14.2",
              package_manager: "npm_and_yarn",
              requirements: [{
                file: "package.json",
                requirement: "0.14.2",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end

          it { is_expected.to eq(Gem::Version.new("0.14.9")) }
        end
      end
    end
  end
end

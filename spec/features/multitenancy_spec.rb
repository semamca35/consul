require "rails_helper"

describe "Multitenancy" do
  before do
    create(:tenant, name: "CONSUL",  subdomain: "public")
    create(:tenant, subdomain: "subdomain")
    Apartment::Tenant.switch! "public"
    Apartment::Tenant.create("subdomain")
  end

  after do
    reset_capybara_host
    Apartment::Tenant.drop("subdomain")
  end

  context "Debates" do
    scenario "Disabled with a feature flag in subdomain" do
      Setting["process.debates"] = true

      Apartment::Tenant.switch("subdomain") do
        Setting["process.debates"] = nil
        expect{ visit debates_path }.to raise_exception(FeatureFlags::FeatureDisabled)
      end

      visit debates_path

      expect(page).to have_selector("#debates")
    end

    scenario "Index for differents tenants" do
      debates_public = [create(:debate, title: "Debate 1"), create(:debate, title: "Debate 2"),
                        create(:debate, title: "Debate 3")]

      visit debates_path

      expect(page).to have_selector("#debates .debate", count: 3)

      debates_public.each do |debate|
        within("#debates") do
          expect(page).to have_content debate.title
          expect(page).to have_content debate.description
          expect(page).to have_css("a[href='#{debate_path(debate)}']", text: debate.title)
        end
      end

      Apartment::Tenant.switch("subdomain") do
        debates_subdomain = [create(:debate, title: "Debate 4"), create(:debate, title: "Debate 5")]

        visit debates_path

        within("#debates") do
          debates_subdomain.each do |debate|
            expect(page).to have_content debate.title
          end

          expect(page).not_to have_content "Debate 1"
          expect(page).not_to have_content "Debate 2"
          expect(page).not_to have_content "Debate 3"
        end
      end
    end

    scenario "Create into Subdomain" do
      Apartment::Tenant.switch("subdomain") do
        author = create(:user)
        login_as(author)

        visit new_debate_path
        fill_in "debate_title", with: "A title for a debate"
        fill_in "debate_description", with: "This is very important because..."
        check "debate_terms_of_service"

        click_button "Start a debate"

        expect(page).to have_content "A title for a debate"
        expect(page).to have_content "Debate created successfully."
        expect(page).to have_content "This is very important because..."
        expect(page).to have_content author.name
        expect(page).to have_content I18n.l(Debate.last.created_at.to_date)
      end

      visit debates_path

      expect(page).not_to have_selector("#debates .debate")
    end

    scenario "Users cannot create debates if they don't belong to that tenant" do
      login_as(create(:user))
      visit root_path

      Apartment::Tenant.switch("subdomain") do
        visit new_debate_path

        expect(page).to have_content "You must sign in or register to continue."
      end
    end
  end

  context "Proposals" do
    scenario "Disabled with a feature flag in subdomain" do
      Setting["process.proposals"] = true

      Apartment::Tenant.switch("subdomain") do
        Setting["process.proposals"] = nil
        expect{ visit proposals_path }.to raise_exception(FeatureFlags::FeatureDisabled)
      end

      visit proposals_path

      expect(page).to have_selector("#proposals")
    end

    scenario "Index in Subdomain lists featured and regular proposals" do
      Setting["feature.featured_proposals"] = true
      Setting["featured_proposals_number"] = 3

      Apartment::Tenant.switch("subdomain") do
        Setting["feature.featured_proposals"] = true
        Setting["featured_proposals_number"] = 3
      end

      create_featured_proposals
      2.times { create(:proposal) }

      visit proposals_path

      expect(page).to have_selector("#proposals .proposal-featured", count: 3)
      expect(page).to have_selector("#proposals .proposal", count: 2)

      Apartment::Tenant.switch("subdomain") do
        visit proposals_path

        expect(page).not_to have_selector("#proposals .proposal-featured")
        expect(page).not_to have_selector("#proposals .proposal")

        create_featured_proposals
        create(:proposal)

        visit proposals_path

        expect(page).to have_selector("#proposals .proposal-featured", count: 3)
        expect(page).to have_selector("#proposals .proposal", count: 1)
      end
    end

    scenario "Create into Subdomain" do
      Apartment::Tenant.switch("subdomain") do
        author = create(:user)
        login_as(author)

        visit new_proposal_path

        fill_in "proposal_title", with: "Help refugees"
        fill_in "proposal_summary", with: "In summary, what we want is..."
        fill_in "proposal_description", with: "This is very important because..."
        fill_in "proposal_video_url", with: "https://www.youtube.com/watch?v=yPQfcG-eimk"
        fill_in "proposal_tag_list", with: "Refugees, Solidarity"
        check "proposal_terms_of_service"

        click_button "Create proposal"

        expect(page).to have_content "Proposal created successfully."
        expect(page).to have_content "Help refugees"
        expect(page).not_to have_content "You can also see more information about improving your campaign"

        click_link "No, I want to publish the proposal"

        expect(page).to have_content "Improve your campaign and get more support"

        click_link "Not now, go to my proposal"

        expect(page).to have_content "Help refugees"
        expect(page).to have_content "In summary, what we want is..."
        expect(page).to have_content "This is very important because..."
        expect(page).to have_content "https://www.youtube.com/watch?v=yPQfcG-eimk"
        expect(page).to have_content author.name
        expect(page).to have_content "Refugees"
        expect(page).to have_content "Solidarity"
        expect(page).to have_content I18n.l(Proposal.last.created_at.to_date)
      end

      visit proposals_path

      expect(page).not_to have_selector("#proposals .proposal-featured")
      expect(page).not_to have_selector("#proposals .proposal")
    end

    scenario "Users cannot create proposals if they don't belong to that tenant" do
      login_as(create(:user))
      visit root_path

      Apartment::Tenant.switch("subdomain") do
        visit new_proposal_path

        expect(page).to have_content "You must sign in or register to continue."
      end
    end
  end

  context "Polls" do
    scenario "Polls listed in each tenant are differents" do
      polls_public = create_list(:poll, 3)

      visit polls_path

      polls_public.each do |poll|
        expect(page).to have_content(poll.name)
      end

      Apartment::Tenant.switch("subdomain") do
        visit polls_path

        expect(page).to have_content("There are no open votings")

        polls_subdomain = create_list(:poll, 2)

        visit polls_path

        polls_subdomain.each do |poll|
          expect(page).to have_content(poll.name)
        end

        expect(page).not_to have_content(polls_public[0].name)
        expect(page).not_to have_content(polls_public[1].name)
        expect(page).not_to have_content(polls_public[2].name)
      end
    end
  end

  context "Votes" do
    context "Debates" do
      scenario "User from other tenant trying to vote debates", :js do
        login_as(create(:user))
        visit root_path

        Apartment::Tenant.switch("subdomain") do
          debate = create(:debate)

          visit_path debates_path, subdomain: "subdomain"

          within("#debate_#{debate.id}") do
            find("div.votes").hover
            expect_message_you_need_to_sign_in
          end
        end
      end
    end

    context "Proposals" do
      scenario "User from other tenant trying to vote proposals", :js do
        login_as(create(:user))
        visit root_path

        Apartment::Tenant.switch("subdomain") do
          proposal = create(:proposal)

          visit_path proposals_path, subdomain: "subdomain"

          within("#proposal_#{proposal.id}") do
            find("div.supports").hover
            expect_message_you_need_to_sign_in
          end

          visit proposal_path(proposal)
          within("#proposal_#{proposal.id}") do
            find("div.supports").hover
            expect_message_you_need_to_sign_in
          end
        end
      end
    end
  end

  context "Authentication" do
    context "Sign up into subdomain" do
      scenario "Success" do
        Apartment::Tenant.switch("subdomain") do
          message = "You have been sent a message containing a verification link. Please click on this link to activate your account."

          visit "/"
          click_link "Register"

          fill_in "user_username",              with: "Manuela Carmena"
          fill_in "user_email",                 with: "manuela@consul.dev"
          fill_in "user_password",              with: "judgementday"
          fill_in "user_password_confirmation", with: "judgementday"
          check "user_terms_of_service"

          click_button "Register"

          expect(page).to have_content message

          confirm_email

          expect(page).to have_content "Your account has been confirmed."
        end
      end

      scenario "Errors on sign up" do
        Apartment::Tenant.switch("subdomain") do
          visit "/"
          click_link "Register"
          click_button "Register"

          expect(page).to have_content error_message
        end
      end
    end

    context "Sign in into subdomain" do
      scenario "sign in with email" do
        Apartment::Tenant.switch("subdomain") do
          create(:user, email: "manuela@consul.dev", password: "judgementday")

          visit "/"
          click_link "Sign in"
          fill_in "user_login",    with: "manuela@consul.dev"
          fill_in "user_password", with: "judgementday"
          click_button "Enter"

          expect(page).to have_content "You have been signed in successfully."
        end
      end

      scenario "not allowed access with user of another tenant" do
        create(:user, email: "manuela@consul.dev", password: "judgementday")

        Apartment::Tenant.switch("subdomain") do
          visit "/"
          click_link "Sign in"
          fill_in "user_login",    with: "manuela@consul.dev"
          fill_in "user_password", with: "judgementday"
          click_button "Enter"

          expect(page).to have_content "Invalid Email or username or password."
        end

        visit "/"
        click_link "Sign in"
        fill_in "user_login",    with: "manuela@consul.dev"
        fill_in "user_password", with: "judgementday"
        click_button "Enter"

        expect(page).to have_content "You have been signed in successfully."
      end
    end
  end
end

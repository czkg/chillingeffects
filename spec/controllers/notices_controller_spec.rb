require 'spec_helper'

describe NoticesController do
  context "#show" do
    it "finds the notice by ID" do
      notice = Notice.new
      Notice.should_receive(:find_visible).with('42').and_return(notice)

      get :show, id: 42

      expect(assigns(:notice)).to eq notice
    end

    context "as HTML" do
      it "renders the show template" do
        stub_find_notice

        get :show, id: 1

        expect(response).to be_successful
        expect(response).to render_template(:show)
      end

      it "renders the rescinded template if the notice is rescinded" do
        stub_find_notice(build(:dmca, rescinded: true))

        get :show, id: 1

        expect(response).to be_successful
        expect(response).to render_template(:rescinded)
      end
    end

    context "as JSON" do
      Notice.type_models.each do |model_class|
        it "returns a serialized notice for #{model_class}" do
          notice = stub_find_notice(model_class.new)
          serializer_class = model_class.active_model_serializer || NoticeSerializer
          serialized = serializer_class.new(notice)
          serializer_class.should_receive(:new).
            with(notice, anything).and_return(serialized)

          get :show, id: 1, format: :json

          json = JSON.parse(response.body)[model_class.to_s.tableize.singularize]
          expect(json).to have_key('id').with_value(notice.id)
          expect(json).to have_key('title').with_value(notice.title)
          expect(json).to have_key('sender_name')
        end
      end

      it "returns id, title and 'Notice Rescinded' as body for a rescinded notice" do
        notice = build(:dmca, rescinded: true)
        stub_find_notice(notice)

        get :show, id: 1, format: :json

        json = JSON.parse(response.body)["dmca"]
        expect(json).to have_key('id').with_value(notice.id)
        expect(json).to have_key('title').with_value(notice.title)
        expect(json).to have_key('body').with_value("Notice Rescinded")
      end
    end

    def stub_find_notice(notice = nil)
      notice ||= Notice.new
      notice.tap { |n| Notice.stub(:find_visible).and_return(n) }
    end
  end

  context "#create" do
    context "format-independent logic" do
      before do
        @submit_notice = double("SubmitNotice").as_null_object
        @notice_params = HashWithIndifferentAccess.new(title: "A title")
      end

      it "initializes a Dmca by default from params" do
        SubmitNotice.should_receive(:new).
          with(Dmca, @notice_params).
          and_return(@submit_notice)

        post :create, notice: @notice_params
      end

      it "uses the type param to instantiate the correct class" do
        SubmitNotice.should_receive(:new).
          with(Trademark, @notice_params).
          and_return(@submit_notice)

        post :create, notice: @notice_params.merge(type: 'trademark')
      end

      it "defaults to Dmca if the type is missing or invalid" do
        invalid_types = ['', 'FlimFlam', 'Object', 'User', 'Hash']

        SubmitNotice.should_receive(:new).
          exactly(5).times.
          with(Dmca, @notice_params).
          and_return(@submit_notice)

        invalid_types.each do |invalid_type|
          post :create, notice: @notice_params.merge(type: invalid_type)
        end
      end
    end

    context "as HTML" do
      it "redirects when saved successfully" do
        stub_submit_notice

        post_create

        expect(response).to redirect_to(:root)
      end

      it "renders the new template when unsuccessful" do
        submit_notice = stub_submit_notice
        submit_notice.stub(:submit).and_return(false)

        post_create

        expect(assigns(:notice)).to eq submit_notice.notice
        expect(response).to render_template(:new)
      end
    end

    context "as JSON" do
      before do
        @ability = Object.new
        @ability.extend(CanCan::Ability)
        @ability.can(:submit, Notice)
        controller.stub(:current_ability) { @ability }
      end

      it "returns unauthorized if one cannot submit" do
        stub_submit_notice
        @ability.cannot(:submit, Notice)

        post_create :json

        expect(response.status).to eq 401
      end

      it "returns a proper Location header when saved successfully" do
        notice = build_stubbed(:dmca)
        submit_notice = stub_submit_notice
        submit_notice.stub(:notice).and_return(notice)

        post_create :json

        expect(response).to be_successful
        expect(response.headers['Location']).to eq notice_url(notice)
      end

      it "returns a useful status code when there are errors" do
        submit_notice = stub_submit_notice
        submit_notice.stub(:submit).and_return(false)

        post_create :json

        expect(response).to be_unprocessable
      end

      it "includes any errors in the response" do
        submit_notice = stub_submit_notice
        submit_notice.stub(:submit).and_return(false)
        submit_notice.stub(:errors).and_return(
          mock_errors(submit_notice.notice, works: "can't be blank")
        )

        post_create :json

        json = JSON.parse(response.body)
        expect(json).to have_key('works').with_value(["can't be blank"])
      end
    end

    private

    def stub_submit_notice
      SubmitNotice.new(Dmca, {}).tap do |submit_notice|
        submit_notice.stub(:submit).and_return(true)
        SubmitNotice.stub(:new).and_return(submit_notice)
      end
    end

    def post_create(format = :html)
      post :create, notice: { title: "A title" }, format: format
    end

    def mock_errors(model, field_errors = {})
      ActiveModel::Errors.new(model).tap do |errors|
        field_errors.each do |field, message|
          errors.add(field, message)
        end
      end
    end
  end
end

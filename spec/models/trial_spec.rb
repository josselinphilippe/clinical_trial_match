require "rails_helper"

describe Trial do
	it "is valid with all required attributes" do
		expect(FactoryGirl.build(:trial)).to be_valid
	end

	it "is invalid without a title" do
		expect(FactoryGirl.build(:trial, :title => "")).to_not be_valid
	end

	it "is invalid without a description" do
		expect(FactoryGirl.build(:trial, :description => "")).to_not be_valid
	end

	it "is invalid without a sponsor" do
		expect(FactoryGirl.build(:trial, :sponsor => "")).to_not be_valid
	end

	it "is invalid without a focus" do
		expect(FactoryGirl.build(:trial, :focus => "")).to_not be_valid
	end

	it "is invalid without a unique nct_id value" do
		FactoryGirl.create(:trial, :nct_id => "12345")
		expect(FactoryGirl.build(:trial, :nct_id => "12345")).to_not be_valid
	end

	it "is invalid without an inclusion criteria" do
		expect(FactoryGirl.build(:trial, :inclusion => "")).to_not be_valid
	end

	context "appends html markup" do
		it "adds header titles to criteria output" do
			trial = FactoryGirl.build(:trial, :inclusion => "\n\nInclusion Criteria:\n\n This is the a test sentence.\n\nExclusion Criteria:\n\n This is the a test sentence. ")
			output = trial.output_criteria
			expect(output).to include("<h4>Inclusion Criteria:</h4>")
			expect(output).to include("<h4>Exclusion Criteria:</h4>")
		end

		it "adds break tags to  detailed description output" do
			trial = FactoryGirl.build(:trial, :detailed_description => "\n\nSentence one.\n\n Sentence two.\n\n")
			output = trial.output_description
			expect(output).to include("<br><br>")
		end
	end

	context "handles age input" do
		it "floors half year values to integers" do
			trial = FactoryGirl.create(:trial, :originalminage => "6 months", :originalmaxage => "18 months")
			expect(trial.minimum_age).to eq(0)
			expect(trial.maximum_age).to eq(1)
		end

		it "floors full number values to integers" do
			trial = FactoryGirl.create(:trial, :originalminage => "12 months", :originalmaxage => "24 months")
			expect(trial.minimum_age).to eq(1)
			expect(trial.maximum_age).to eq(2)
		end
	end

	context "filters trial listing" do
		it "by #search_for" do
			trial1 = FactoryGirl.create(:trial, :title => "This is SpecialWord im looking up.")
			trial2 = FactoryGirl.create(:trial, :description => "This is specialword im looking up.")
			trial3 = FactoryGirl.create(:trial)
			expect(Trial.search_for("specialword")).to eq [trial1,trial2]
		end

		it "by #control?" do
			trial1 = FactoryGirl.create(:trial, :healthy_volunteers => "Accepts Healthy Volunteers")
			trial2 = FactoryGirl.create(:trial)
			expect(Trial.control?("control")).to eq [trial1]
		end

		context "by #gender" do
			it "filters for males" do
				trial1 = FactoryGirl.create(:trial, :gender => "Male")
				trial2 = FactoryGirl.create(:trial, :gender => "Female")
				expect(Trial.gender("male")).to eq [trial1]
			end

			it "filters for females" do
				trial1 = FactoryGirl.create(:trial, :gender => "Male")
				trial2 = FactoryGirl.create(:trial, :gender => "Female")
				expect(Trial.gender("female")).to eq [trial2]
			end

			it "displays all with both filter" do
				trial1 = FactoryGirl.create(:trial, :gender => "Male")
				trial2 = FactoryGirl.create(:trial, :gender => "Female")
				expect(Trial.gender("both")).to eq [trial1,trial2]
			end
		end

	# scope :gender, -> (gender) {
	# 	if gender == "male"
	# 		where(gender: ["Male", "Both"])
	# 	elsif gender == "female"
	# 		where(gender: ["Female", "Both"])

	# 	end
	# }
	end
end
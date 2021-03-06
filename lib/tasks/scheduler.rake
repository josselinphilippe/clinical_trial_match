namespace :importer do
    desc "Task for Heroku Scheduler to reset last import date"
    task :clear_import_date => :environment do
        puts "Resetting date to 1900"
        @import = Import.new
        @import.datetime = "Mon, 1 Jan 1900 00:00:04 UTC +00:00"
        @import.valid_trials = 0
        @import.valid_sites = 0
        @import.save
        puts "The Date is now #{Import.last.datetime}"
    end

    desc "Task for Heroku Scheduler to send test email"
    task :test_email => :environment do
        puts "Sending Email"
        Newmatch.new_match_report.deliver
    end

    desc "Rewind import date based on time parameter"
    task :rewind_import_date,[:amount_of_time] => :environment do |t, args|
        puts "Resetting date to your parameter"
        @import = Import.new
        @import.datetime = Time.now - args['amount_of_time']
        @import.valid_trials = 0
        @import.valid_sites = 0
        @import.save
        puts "The Date is now #{Import.last.datetime}"
    end


    desc "Task for Heroku Scheduler to clear all trials"
    task :delete_trials => :environment do
        puts "Removing all trials"
        Trial.delete_all
        Site.delete_all
        puts "There are #{Trial.all.count} trials and #{Site.all.count} sites"
    end


    desc "Task for Heroku Scheduler to import trials and takes parameter for # of trials"
    task :import, [:number_of_trials] => :environment do |t, args|
        require 'nokogiri'
        require 'rest-client'
        require 'uri'
        require 'zip'

        # HELPER METHOD FOR IDENTIFYING DIRECTORY DEPTH
        def get_from_xpath(path_and_name, directory, merge=false)
            if directory.xpath("#{path_and_name}").nil?
                return ""
            elsif merge
                tmpValue = ""
                directory.xpath("#{path_and_name}").each do |item|
                    tmpValue << item.text + ", "
                end
                return tmpValue[0..-3]
            else
                return directory.xpath("#{path_and_name}").text
            end
        end

        # HELPER METHODs FOR AGE WITH N/A VALUES
        def set_minvalue_for_age(minval)
            if minval == "N/A"
                return "0 Years"
            else
                return minval
            end
        end

        def set_maxvalue_for_age(maxval)
            if maxval == "N/A"
                return "100 Years"
            else
                return maxval
            end
        end


        encoded_condition = URI.encode(ClinicalTrialMatcher::Application.config.importer_query)
        remove_unknown = ClinicalTrialMatcher::Application.config.remove_unknown
        #http://clinicaltrials.gov/ct2/results/download?down_stds=all&down_typ=study&recr=Open&no_unk=Y&cond=brain%20tumor&show_down=Y
        starting_url = "http://clinicaltrials.gov/ct2/results/download?down_stds=all&down_typ=study&recr=Open&no_unk=#{remove_unknown}&cond=#{encoded_condition}&show_down=Y"
        puts "Downloading file"
        `curl "#{starting_url}" > "#{Rails.root}/tmp/trial_download.zip"`

        # @modified_trial_counter tracks new and updated trials
        # @unmodified_trial_counter tracks trials that have not been updated since last import
        # @invalid_trial_counter tracks recently modified trials that are incomplete
        @modified_trial_counter = 0
        @unmodified_trial_counter = 0
        @invalid_trial_counter = 0


        @site_counter = 0
        last_import_date = Import.last.datetime unless Import.last.nil?

        Zip::File.open("#{Rails.root}/tmp/trial_download.zip") do |ar|
          @num_xml_files = ar.count # number of entries
          puts "Looping through #{@num_xml_files} xml files"

          ar.each_with_index do |file, index|
            break if (args['number_of_trials'].present? && (@modified_trial_counter >= args['number_of_trials'].to_i))

            puts "Processing #{file}: #{index} / #{@num_xml_files}"
            entry_name = ar.name # get entry name from archive
            f = file.get_input_stream.read
            doc = Nokogiri::XML(f)
            root = doc.root
            temp_nct_id = get_from_xpath("//nct_id",root)

            if last_import_date.present? && (get_from_xpath("lastchanged_date",root) < last_import_date)
                puts "Fail: Changes Older than Last Import"
                @unmodified_trial_counter += 1
                f = ""
            else
                @trial = Trial.where("nct_id = ?", temp_nct_id).present? ? Trial.where("nct_id = ?", temp_nct_id).first : Trial.new
                @trial.title = get_from_xpath("brief_title",root)
                @trial.description = get_from_xpath("brief_summary/textblock",root)
                @trial.detailed_description = get_from_xpath("detailed_description/textblock",root)
                @trial.sponsor = get_from_xpath("sponsors/lead_sponsor/agency",root)
                @trial.focus = get_from_xpath("condition",root,true)
                @trial.country = get_from_xpath("location_countries/country",root,true)  #redundant
                @trial.nct_id = get_from_xpath("//nct_id",root)
                @trial.official_title = get_from_xpath("official_title",root)
                @trial.agency_class = get_from_xpath("//agency_class",root)
                @trial.overall_status = get_from_xpath("//overall_status",root)
                @trial.phase = get_from_xpath("//phase",root)
                @trial.study_type = get_from_xpath("//study_type",root)
                @trial.condition = get_from_xpath("condition",root) #redundant
                @trial.inclusion = get_from_xpath("//criteria/textblock",root)
                @trial.exclusion = get_from_xpath("//criteria/textblock",root)
                @trial.gender = get_from_xpath("//gender",root)
                @trial.healthy_volunteers = get_from_xpath("//healthy_volunteers",root)
                @trial.overall_contact_name = get_from_xpath("//overall_contact/last_name",root)
                @trial.overall_contact_phone = get_from_xpath("//overall_contact/phone",root)
                @trial.overall_contact_email = get_from_xpath("//overall_contact/email",root)
                @trial.location_countries = get_from_xpath("location_countries/country",root,true)
                @trial.link_url = get_from_xpath("//link/url",root)
                @trial.link_description = get_from_xpath("//link/description",root)
                @trial.firstreceived_date = get_from_xpath("firstreceived_date",root)
                @trial.lastchanged_date = get_from_xpath("lastchanged_date",root)
                @trial.verification_date = get_from_xpath("verification_date",root)
                @trial.keyword = get_from_xpath("keyword",root,true)
                @trial.is_fda_regulated = get_from_xpath("is_fda_regulated",root)
                @trial.has_expanded_access = get_from_xpath("has_expanded_access",root)

                # FOR AGE: SEPARATELY STORES IMPORTED VALUE WITH MONTHS VS ALGORITHM VALUEs
                @trial.originalminage = set_minvalue_for_age(get_from_xpath("//minimum_age",root))
                @trial.originalmaxage = set_maxvalue_for_age(get_from_xpath("//maximum_age",root))

                doc.xpath("//location",root).each do |site|
                    puts "   Processing site:#{@site_counter} "

                    @site_counter += 1
                    @site = Site.new
                    @site.facility = get_from_xpath("facility/name",site)
                    @site.city = get_from_xpath("facility/address/city",site)
                    @site.state = get_from_xpath("facility/address/state",site)
                    @site.zip_code = get_from_xpath("facility/address/zip",site)
                    @site.country = get_from_xpath("facility/address/country",site)
                    @site.status = get_from_xpath("status",site)

                    @site.contact_name = get_from_xpath("contact/last_name",site)
                    @site.contact_phone = get_from_xpath("contact/phone",site)
                    @site.contact_phone_ext = get_from_xpath("contact/phone_ext",site)
                    @site.contact_phone_email = get_from_xpath("contact/email",site)

                    @trial.sites << @site
                    @site.save
                end

                if @trial.save
                    @modified_trial_counter += 1
                    puts "Saved Successfully"

                else
                    @trial.valid?
                    puts "Failed to save"
                    @trial.errors.each {|error| puts error }
                    @invalid_trial_counter += 1
                end

                f = ""
                puts "\n"
            end

          end

        end

        # TIMESTAMP THE IMPORT RUN
        @import = Import.new
        @import.num_xml_files = @num_xml_files
        @import.datetime = Time.new
        @import.valid_trials = @modified_trial_counter
        @import.unmodified_trials = @unmodified_trial_counter
        @import.invalid_trials = @invalid_trial_counter
        @import.valid_sites = @site_counter
        @import.save

        puts "Modified #{@modified_trial_counter} trials"
        puts "Unmodified #{@unmodified_trial_counter} trials"
        puts "Invalid #{@invalid_trial_counter} trials"
        puts "_________________________________________"
        puts "Total: #{@modified_trial_counter.to_i + @unmodified_trial_counter.to_i + @invalid_trial_counter.to_i} trials"
        puts "Processed #{@num_xml_files} xml files"

        puts "There are #{Trial.all.count} trials total"
        puts "There are #{Site.all.count} sites total"
        puts "Sending import email"

        Newmatch.new_match_report.deliver

        puts "Deleting zip folder"
        File.delete("#{Rails.root}/tmp/trial_download.zip") if File.exist?("#{Rails.root}/tmp/trial_download.zip")
        puts "Completed task"

    end

end


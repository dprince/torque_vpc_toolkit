require 'rexml/document'
require 'rexml/xpath'
require 'json'

require 'chef-vpc-toolkit'

module TorqueVPCToolkit

	TORQUE_VPC_TOOLKIT_ROOT = File.dirname(File.expand_path("./", File.dirname(__FILE__)))

	include ChefVPCToolkit

	def self.jobs_list(xml)

		list=[]
		dom = REXML::Document.new(xml)

		REXML::XPath.each(dom, "//job") do |job|
			job_attrs = {
				"id" => job.elements["id"].text,
				"description" => job.elements["description"].text,
				"queue-job-id" => job.elements["queue-job-id"].text,
				"resources" => job.elements["resources"].text,
				"additional-attrs" => job.elements["additional-attrs"].text,
				"status" => job.elements["status"].text
			}

			stdout=job.elements["stdout"]
			job_attrs.store("stdout", stdout.text) if stdout

			stderr=job.elements["stderr"]
			job_attrs.store("stderr", stderr.text) if stderr

			list << job_attrs
		end

		list

	end

	def self.submit_job(configs, script, description, resources, additional_attrs="")

		Util.raise_if_nil_or_empty(configs, "ssh_gateway_ip")
		Util.raise_if_nil_or_empty(configs, "torque_job_control_username")
		Util.raise_if_nil_or_empty(configs, "torque_job_control_password")

		post_data={
			"job[description]" => description
		}
		if not resources.nil? and not resources.empty? then
			post_data.store("job[resources]", resources)
		end
		if not additional_attrs.nil? and not additional_attrs.empty? then
			post_data.store("job[additional_attrs]", additional_attrs)
		end

		file_data={
			"job[script_file_upload]" => script
		}

		resp=HttpUtil.file_upload(
            "https://"+configs["ssh_gateway_ip"]+"/jobs.xml",
            file_data,
            post_data,
            configs["torque_job_control_username"],
            configs["torque_job_control_password"]
        )

	end

	def self.node_states(xml)

		node_states={}
		dom = REXML::Document.new(xml)

		REXML::XPath.each(dom, "//Node") do |job|
			node_states.store(job.elements["name"].text, job.elements["state"].text)
		end

		node_states

	end

	# default timeout of 20 minutes
	def self.poll_until_online(ip, timeout=1200, configs=Util.load_configs)

		online = false
		count=0
		until online or (count*20) >= timeout.to_i do
			count+=1
			xml=""
			begin
				xml=HttpUtil.get(
					"https://#{ip}/nodes",
					configs["torque_job_control_username"],
					configs["torque_job_control_password"]
				)
			rescue
				sleep 20
				next
			end

			jobs=TorqueVPCToolkit.node_states(xml)

			online=true
			jobs.each_pair do |name, state|
				if state != "free" then
					online=false
				end
			end
			if not online
				yield jobs if block_given?
				sleep 20
			end
		end
		if (count*20) >= timeout.to_i then
			raise "Timeout waiting for job control to come online."
		end

	end

	def self.print_job(hash)

		puts "Job ID: #{hash["id"]}"
		puts "description: #{hash["description"]}"
		puts "Queue job ID: #{hash["queue-job-id"]}"
		puts "Resources: #{hash["resources"]}"
		puts "Additional Attrs: #{hash["additional-attrs"]}"
		puts "Status: #{hash["status"]}"
		puts "--"

	end

	def self.submit_all(configs, base_config_file="jobs.json")

                config_file=CHEF_VPC_ROOT + File::SEPARATOR + "config" + File::SEPARATOR + base_config_file
		if not File.exists?(config_file) then
			puts "config file: " + config_file + " is missing. No jobs scheduled."
			return
		end

		json_hash=JSON.parse(IO.read(config_file))

		# hash for job_name/job_id's (used for variable substitution)
		jobid_vars={}
		jobs_dir=CHEF_VPC_ROOT + File::SEPARATOR + "jobs" + File::SEPARATOR

		json_hash.each do |job|
			script=job["script"]
			name=job["name"]
			if File.exists?(jobs_dir+script) then
				resources=self.replace_jobid_vars(job["resources"], jobid_vars)
				additional_attrs=self.replace_jobid_vars(job["additional_attrs"], jobid_vars)
				xml=self.submit_job(configs, jobs_dir+script, name, resources, additional_attrs)
				job_hash=TorqueVPCToolkit.jobs_list(xml)[0]
				if jobid_vars.has_key?(name) then
					raise "A unique job name must be specified in " + base_config_file
				else
					jobid_vars.store(name, job_hash["queue-job-id"])
				end
				puts "\tJob ID "+job_hash["id"]+ " submitted."
				
			else
				raise "Job script '#{script}' does not exists."
			end
		end

	end

	def self.job_hash(vpn_gateway, job_id, configs=Util.load_configs)
		if job_id.nil? or job_id.empty? then
			raise "A valid job_id is required."
		end
		xml=HttpUtil.get(
			"https://#{vpn_gateway}/jobs/#{job_id}.xml",
			configs["torque_job_control_username"],
			configs["torque_job_control_password"]
		)
		TorqueVPCToolkit.jobs_list(xml)[0]

	end

	# default timeout of 20 minutes
	def self.poll_until_jobs_finished(ip, timeout=1200, configs=Util.load_configs)
		count=0
		until (count*20) >= timeout.to_i do
			count+=1
			xml=""
			begin
				xml=HttpUtil.get(
					"https://#{ip}/jobs.xml",
					configs["torque_job_control_username"],
					configs["torque_job_control_password"]
				)
			rescue
				sleep 20
				next
			end

			jobs=TorqueVPCToolkit.jobs_list(xml)
			all_jobs_finished = true
			jobs.each do |job|	
				if job["status"] == "Failed" then
					raise "Job ID #{job['id']} failed."
				elsif job["status"] != "Completed" then
					all_jobs_finished = false
				end
			end
			if all_jobs_finished then
				break
			else
				yield jobs if block_given?
				sleep 20
			end
		end
		if (count*20) >= timeout.to_i then
			raise "Timeout waiting for jobs to finish."
		end

	end

	private
	def self.replace_jobid_vars(str, vars)
		return nil if str.nil?
		vars=vars.sort { |a,b| b[0].length <=> a[0].length }
		vars.each do |arr|
			regex=Regexp.new("\\$#{arr[0]}")
			str=str.gsub(regex, arr[1])
		end
		str
	end

end

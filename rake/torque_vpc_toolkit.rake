namespace :job do

	desc "Submit a job (requires: SCRIPT=<job_script_name>)"
	task :submit do

		script=ENV['SCRIPT']
		resources=ENV['RESOURCES']
		additional_attrs=ENV['ATTRIBUTES']

		configs=CloudToolkit.load_configs
		hash=CloudToolkit.hash_for_group(configs)
		configs["ssh_gateway_ip"]=hash["vpn-gateway"]
		configs.merge!(ChefInstaller.job_control_credentials(hash['vpn-gateway']))

		xml=JobControl.submit_job(configs, "jobs/#{script}", script, resources, additional_attrs)
		job_hash=JobControl.jobs_list(xml)[0]
		JobControl.print_job(job_hash)

	end

	desc "Submit all jobs (specify job config file with JOB_CONFIG, uses jobs.json by default)"
	task :submit_all do
                job_config=ENV['JOB_CONFIG']              
                if job_config.nil? then
                  job_config="jobs.json"
                end

		configs=CloudToolkit.load_configs
		hash=CloudToolkit.hash_for_group(configs)
		configs["ssh_gateway_ip"]=hash["vpn-gateway"]
		configs.merge!(ChefInstaller.job_control_credentials(hash['vpn-gateway']))
		xml=JobControl.submit_all(configs)

	end

	desc "List jobs"
	task :list do

		configs=CloudToolkit.load_configs
		hash=CloudToolkit.hash_for_group(configs)
		configs.merge!(ChefInstaller.job_control_credentials(hash['vpn-gateway']))
		xml=HttpUtil.get(
			"https://"+hash["vpn-gateway"]+"/jobs.xml",
			configs["torque_job_control_username"],
			configs["torque_job_control_password"]
		)
		jobs=JobControl.jobs_list(xml)
		puts "Jobs:"
		jobs.each do |job|
			puts "\t#{job['id']}: #{job['description']} (#{job['status']})"
		end

	end

	desc "List node states"
	task :node_states do

		configs=CloudToolkit.load_configs
		hash=CloudToolkit.hash_for_group(configs)
		configs.merge!(ChefInstaller.job_control_credentials(hash['vpn-gateway']))
		xml=HttpUtil.get(
			"https://"+hash["vpn-gateway"]+"/nodes",
			configs["torque_job_control_username"],
			configs["torque_job_control_password"]
		)
		node_states=JobControl.node_states(xml)
		puts "Nodes:"
		node_states.each_pair do |name, state|
			puts "\t#{name}: #{state}"
		end

	end

	desc "Poll/loop until job controller is online"
	task :poll_controller do
		timeout=ENV['CONTROLLER_TIMEOUT']
		if timeout.nil? or timeout.empty? then
			timeout=1200
		end

		configs=CloudToolkit.load_configs
		hash=CloudToolkit.hash_for_group(configs)
		configs.merge!(ChefInstaller.job_control_credentials(hash['vpn-gateway']))

		puts "Polling for job controller to come online (this may take a couple minutes)..."
		nodes=nil
		JobControl.poll_until_online(hash["vpn-gateway"], timeout, configs) do |nodes_hash|
			if nodes != nodes_hash then
				nodes = nodes_hash
				nodes_hash.each_pair do |name, state|
					puts "\t#{name}: #{state}"
				end
				puts "\t--"
			end
		end
		puts "Job controller online."
	end

	desc "Poll/loop until jobs finish"
	task :poll_jobs do
		timeout=ENV['JOBS_TIMEOUT']
		if timeout.nil? or timeout.empty? then
			timeout=3600
		end

		configs=CloudToolkit.load_configs
		hash=CloudToolkit.hash_for_group(configs)
		configs.merge!(ChefInstaller.job_control_credentials(hash['vpn-gateway']))

		puts "Polling for jobs to finish running..."
		JobControl.poll_until_jobs_finished(hash["vpn-gateway"], timeout, configs)
		puts "Jobs finished."
	end

	desc "Print job logs for the specified JOB_ID."
	task :log do
		job_id=ENV['JOB_ID']

		configs=CloudToolkit.load_configs
		hash=CloudToolkit.hash_for_group(configs)
		configs.merge!(ChefInstaller.job_control_credentials(hash['vpn-gateway']))
		job=JobControl.job_hash(hash["vpn-gateway"], job_id, configs)

		puts "--"
		puts "Job ID: #{job['id']}"
		puts "Description: #{job['description']}"
		puts "Status: #{job['status']}"
		puts "--"
		puts "Stdout:\n#{job['stdout']}"
		puts "--"
		puts "Stderr:\n#{job['stderr']}"

	end

	desc "Create a new server group and run all jobs."
	task :create_and_run_all => ["create"] do

		Rake::Task['job:poll_controller'].invoke
		Rake::Task['share:sync'].invoke
		Rake::Task['job:submit_all'].invoke
		Rake::Task['job:poll_jobs'].invoke
		cleanup=ENV['CLEANUP']

		if cleanup then
			Rake::Task['cloud:delete'].invoke
		end

	end

end

desc "Create a server group, install chef, sync share data, run jobs."
task :all do

	puts "DEPRECATED: The 'all' task is deprecated. Use 'job:create_and_run_all' instead."
	Rake::Task['job:create_and_run_all'].invoke

end

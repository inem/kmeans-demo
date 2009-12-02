# ami-bf5eb9d6 - ec2cluster
# ami-ccf615a5 - elasticwulf

# Short Ruby example using the ec2cluster REST API and
# the right_aws Amazon S3 module to run a MPI job on EC2
#
# To run the demo:
#
# 1. Set your credentials in config.yml
#
# 2. install the gem dependencies:
#     $ gem install right_http_connection --no-rdoc --no-ri
#     $ gem install right_aws --no-rdoc --no-ri
#     $ gem install activeresource --no-ri --no-rdoc
#     $ gem install cliaws --no-ri --no-rdoc
#
# 3. Run this ruby script
#     $ ruby kmeans.rb
#
# code/Simple_Kmeans.zip - contains the kmeans MPI C source
# we want to compile and execute on the cluster.
#
# code/run_kmeans.sh - bash script executed on EC2
# which unzips the MPI source code, compiles it,
# and runs it on all nodes in the cluster.

require 'rubygems'
require 'active_resource'
require 'cliaws'
require 'ostruct'

# Uncomment this to debug ActiveResource connection
# class ActiveResource::Connection
#   # Creates new Net::HTTP instance for communication with
#   # remote service and resources.
#   def http
#     http = Net::HTTP.new(@site.host, @site.port)
#     http.use_ssl = @site.is_a?(URI::HTTPS)
#     http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl
#     http.read_timeout = @timeout if @timeout
#     #Here's the addition that allows you to see the output
#     http.set_debug_output $stderr
#     return http
#   end
# end

# ---------------------------------------------------
# Set AWS credentials and ec2cluster service & job info
# ---------------------------------------------------
CONFIG = OpenStruct.new(YAML.load_file("config.yml")).freeze
ENV['AWS_SECRET_ACCESS_KEY'] = CONFIG.aws_secret_access_key
ENV['AWS_ACCESS_KEY_ID'] = CONFIG.aws_access_key_id

# Specify input data, zip file containing code, and bash script to run the MPI job
sample_input_files = ["input/color100.txt", "code/Simple_Kmeans.zip", "code/run_kmeans.sh" ]

# Specify output files produced after command is run on cluster
# You can include path relative to working directory if needed, for example "outputdir/file1.out"
expected_outputs = ["color100.txt.membership", "color100.txt.cluster_centres"]

# Indicate desired output path, if any:
out_path = "test/output/#{Time.now.strftime('%m%d%y%H%M')} "

# ---------------------------------------------------
# Upload Input files to Amazon S3
# ---------------------------------------------------

puts "Uploading files to S3"
sample_input_files.each do |infile|
  puts "uploading: " + infile
  Cliaws.s3.put(File.open(infile, "rb"), "#{CONFIG.bucket}/test/#{infile}")
end

# ---------------------------------------------------
# Submit the MPI Job
# ---------------------------------------------------
puts "Running Job command..."
# Use ActiveResource to communicate with the ec2cluster REST API
class Job < ActiveResource::Base
  self.site = CONFIG.rest_url
  self.user = CONFIG.admin_user
  self.password = CONFIG.admin_password
  self.timeout = 5
end

# Submit a job request to the API using just the required parameters
job = Job.new(:name => "Kmeans demo", 
  :description => "Simple Kmeans C MPI example", 
  :input_files => sample_input_files.map{|f| "#{CONFIG.bucket}/test/#{f}"}.join(" "), 
  :commands => "bash run_kmeans.sh", 
  :output_files => expected_outputs.join(" "), 
  :output_path => out_path, 
  :number_of_instances => 2, 
  :instance_type => "m1.small")

  # Some examples of other optional parameters for Job.new()
  # ------------------------------------
  # master_ami => "ami-bf5eb9d6"
  # worker_ami => "ami-bf5eb9d6"
  # user_packages => "python-setuptools python-docutils"
  # availability_zone => "us-east-1a"
  # keypair => CONFIG["keypair"]
  # mpi_version => "openmpi"
  # shutdown_after_complete => false


puts job.inspect
job.save # Saving submits the job description to the REST service  
job_id = job.id

puts "Job ID: " + job.id.to_s # returns the job ID
puts "State: " + job.state # current state of the job
puts "Progress: " + job.progress unless job.progress.nil? # more granular description of the current job progress

# Loop, waiting for the job to complete.  
puts "Waiting for job to complete..."
until job.state == 'complete' do
  begin   
    job = Job.find(job_id)
    puts "[State]: " + job.state + " [Progress]: " + job.progress unless job.progress.nil?
  rescue ActiveResource::TimeoutError  
    puts "TimeoutError calling REST server..."  
  end
  sleep 5  
end

# Wrap this with error handling for real job submissions
# and cancel job if it takes to long..
# A cancellation can be sent as follows:  job.put(:cancel)

# ---------------------------------------------------
# Download Output Files from S3
# ---------------------------------------------------
puts "Job complete, downloading results from S3"
# If the job finished successfully, fetch the output files from our S3 bucket
expected_outputs.each do |outfile|
  puts "fetching: " + outfile
  filestream = File.new(outfile, File::CREAT|File::RDWR)
  output = Cliaws.s3.get("#{CONFIG.bucket}/#{out_path}/#{outfile}")
  filestream.write output
  filestream.close  
end






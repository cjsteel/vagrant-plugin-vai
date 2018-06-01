require "vagrant/util/platform"
module VagrantPlugins
  module Vai
    class Provisioner < Vagrant.plugin("2", :provisioner)

      def initialize(machine, config)
        super
        @logger = Log4r::Logger.new("vagrant::provisioners::ansible")
      end
      def provision
        @machine.ui.info("Inventory sucessfully written to #{setup_inventory_file()}")
      end

      protected
      # Auto-generate "safe" inventory file based on Vagrantfile,
      def setup_inventory_file
        #options << "--sudo" if config.sudo
        #options << "--sudo-user=#{config.sudo_user}" if config.sudo_user
        #"ANSIBLE_HOST_KEY_CHECKING" => "#{config.host_key_checking}",

        # Managed machines
        inventory_machines = {}
        generated_inventory_dir = Pathname.new(config.inventory_dir)
        FileUtils.mkdir_p(generated_inventory_dir) unless File.directory?(generated_inventory_dir)
        generated_inventory_filename = config.inventory_filename ? config.inventory_filename : 'vagrant_ansible_inventory'
        generated_inventory_file = generated_inventory_dir.join(generated_inventory_filename)
        generated_inventory_file.open('w') do |file|
          file.write("# Generated by Vagrant\n\n")

          @machine.env.active_machines.each do |am|
            begin
              m = @machine.env.machine(*am)
              m_ssh_info = m.ssh_info
              if !m_ssh_info.nil?
                file.write("#{m.name} ansible_host=#{m_ssh_info[:host]} ansible_port=#{m_ssh_info[:port]} "\
                  "ansible_ssh_private_key_file=#{m_ssh_info[:private_key_path][0]} ansible_user=#{m_ssh_info[:username]}\n")
                inventory_machines[m.name] = m
              else
                @logger.error("Auto-generated inventory: Impossible to get SSH information for machine '#{m.name} (#{m.provider_name})'. This machine should be recreated.")
                # Let a note about this missing machine
                file.write("# MISSING: '#{m.name}' machine was probably removed without using Vagrant. This machine should be recreated.\n")
              end
            rescue Vagrant::Errors::MachineNotFound => e
              @logger.info("Auto-generated inventory: Skip machine '#{am[0]} (#{am[1]})', which is not configured for this Vagrant environment.")
            end
          end

          # Write out groups information.
          # All defined groups will be included, but only supported
          # machines and defined child groups will be included.
          # Group variables are intentionally skipped.
          groups_of_groups = {}
          defined_groups = []

          config.groups.each_pair do |gname, gmembers|
            # Require that gmembers be an array
            # (easier to be tolerant and avoid error management of few value)
            gmembers = [gmembers] if !gmembers.is_a?(Array)

            if gname.end_with?(":children")
              groups_of_groups[gname] = gmembers
              defined_groups << gname.sub(/:children$/, '')
            elsif !gname.include?(':vars')
              defined_groups << gname
              file.write("\n[#{gname}]\n")
              gmembers.each do |gm|
                file.write("#{gm}\n") if inventory_machines.include?(gm.to_sym)
              end
            end
          end

          defined_groups.uniq!
          groups_of_groups.each_pair do |gname, gmembers|
            file.write("\n[#{gname}]\n")
            gmembers.each do |gm|
              file.write("#{gm}\n") if defined_groups.include?(gm)
            end
          end
        end
        return generated_inventory_file.to_s
      end
    end
  end
end


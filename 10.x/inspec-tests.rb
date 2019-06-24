control 'final-image' do
  title 'Ensure the Debian QEMU image is correctly configured'

  describe sys_info do
  its('hostname') { should eq 'kitchen-ci' }
  end

  describe file('/var/lib/cloud/instance/datasource') do
  its('content') { should match 'DataSourceNone' }
  end

  describe command('systemctl status') do
  its('stdout') { should match 'State: running' }
  end
end

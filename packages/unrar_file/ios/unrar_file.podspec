#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'unrar_file'
  s.version          = '0.0.1'
  s.summary          = 'Archive a rar file using junrar android and Unrarkit in ios code on github.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'https://github.com/syedecryptr/unrar_file'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'syedecryptr' => 'syedecryptr@gmail.com' }
  s.source           = { :path => '.' }


  s.source_files = [
  'Classes/**/*',
  ]

  s.dependency 'Flutter'

  s.dependency 'UnrarKit'
  s.ios.deployment_target = '9.0'


end

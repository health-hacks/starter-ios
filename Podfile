source 'https://github.com/CocoaPods/Specs.git'

platform :ios, '9.0'
use_frameworks!

def installablePods
    pod "RealmSwift"
    pod "Alamofire", "~> 4.0"
    pod "SwiftCloudant"
	pod "CHCSVParser"
end

target 'Starter App' do
    installablePods
end

post_install do |installer|
    installer.pods_project.root_object.attributes["ORGANIZATIONNAME"] = "IBM"
end
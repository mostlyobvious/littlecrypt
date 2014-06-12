require 'openssl'

module LittleCrypt
  class Item
    def self.load(data_bag, secret_name, coder = Coder.new)
      encrypted_keys   = data_bag_item(data_bag, "#{secret_name}_keys")
      node_private_key = File.read('/etc/chef/node.key')
      secret_key       = coder.decrypt(node_private_key, encrypted_keys[node.name])
      Chef::EncryptedDataBagItem.new(data_bag_item(data_bag, secret_name), secret_key)[secret_name]
    end
  end

  class Coder
    def encrypt(public_key_data, data)
      OpenSSL::PKey::RSA.new(public_key_data).public_encrypt(data)
    end

    def decrypt(private_key_data, data)
      OpenSSL::PKey::RSA.new(private_key_data).private_decrypt(data)
    end
  end

  class EncryptSecretForNodes
    def initialize(root_path, coder = Coder.new)
      @coder     = coder
      @root_path = root_path
    end

    def call(data_bag, secret_name, node_names, secret)
      node_keys   = node_names.map { |name| JSON.load(@root_path.join("nodes", "#{name}.json").read)["public_key"] }
      kitchen_key = Pathname.new(@root_path).join('chef.key').read
      (node_keys + [kitchen_key]).map do |public_key_data|
        Chef::EncryptedDataBagItem.encrypt_data_bag_item({secret_name => secret}, public_key_data)
      end
    end
  end

  class DecryptSecretForKitchen
    def initialize(root_path, coder = Coder.new)
      @coder     = coder
      @root_path = root_path
    end

    def call(data_bag, secret_name)
      private_key_data = Pathname.new(@root_path).join('chef.key').read
      encrypted_keys   = data_bag_item(data_bag, "#{secret_name}_keys")
      secret_key       = @coder.decrypt(private_key_data, encrypted_keys['kitchen'])
      Chef::EncryptedDataBagItem.new(data_bag_item(data_bag, secret_name), secret_key)[secret_name]
    end

    def data_bag_item(name, key)
      JSON.load(Pathname.new(@root_path).join('data_bags', name))[key]
    end
  end
end
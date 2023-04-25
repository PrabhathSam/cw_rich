raise "Please install CarrierWave: github.com/carrierwaveuploader/carrierwave" unless Object.const_defined?(:CarrierWave)
require 'rich/utils/file_size_validator'
require 'rich/backends/rich_file_uploader'

module Rich
  module Backends
    module CarrierWave
      extend ActiveSupport::Concern

      included do
        mount_uploader :rich_file_file_name, RichFileUploader

        # before_validation :update_rich_file_attributes

        # validate :check_content_type
        # validates :rich_file_file_name,
        #   :presence => true,
        #   :file_size => {
        #     :maximum => 15.megabytes.to_i
        #   }

        # after_save :clear_uri_cachev




        validates_attachment_presence :rich_file, unless: :is_a_folder?
        validate :check_content_type, unless: :is_a_folder?
        validates_attachment_size :rich_file, :less_than=>15.megabyte, :message => "must be smaller than 15MB" , unless: :is_a_folder?

        before_create :clean_file_name, unless: :is_a_folder?

        after_create :cache_style_uris_and_save
        before_update :cache_style_uris


      end

      def rich_file
        self.rich_file_file_name
      end

      def rich_file=(val)
        self.rich_file_file_name = val
      end

      def filename
        rich_file.file.filename
      end

      # used for skipping folders
      def is_a_folder?
        self.rich_file_content_type == 'folder'
      end

      def set_styles
        if self.simplified_type=="image" || self.rich_file_content_type.to_s["image"]
          Rich.image_styles
        elsif self.simplified_type=="video" || self.rich_file_content_type.to_s["video"]
          Rich.video_styles
        else
          {}
        end
      end

      def uri_cache
        uri_cache_attribute = read_attribute(:uri_cache)
        if uri_cache_attribute.blank?
          uris = {}

          rich_file.versions.each do |version|
            uris[version[0]] = rich_file.url(version[0].to_sym, false)
          end

          # manualy add the original size
          uris["original"] = rich_file.url

          uri_cache_attribute = uris.to_json
          write_attribute(:uri_cache, uri_cache_attribute)
        end
        uri_cache_attribute
      end

      def rename!(new_filename_without_extension)
        unless simplified_type == 'folder'
          new_filename = new_filename_without_extension + File.extname(rich_file_file_name)
          rename_files!(new_filename)
        else
          new_filename = new_filename_without_extension
        end
        update_column(:rich_file_file_name, new_filename)
        cache_style_uris_and_save
        new_filename
      end

      # def rename!(new_filename_without_extension)
      #   new_filename = new_filename_without_extension + '.' + rich_file.file.extension
      #   rename_files!(new_filename)
      #   rich_file.model.update_column(:rich_file_file_name, new_filename)
      #   clear_uri_cache
      #   new_filename
      # end

      private

      # def rename_files!(new_filename)
      #   rename_file!(rich_file, new_filename)
      #   rich_file.versions.keys.each do |version|
      #     rename_file!(rich_file.send(version), "#{version}_#{new_filename}")
      #   end
      # end


      def rename_files!(new_filename)
        (rich_file.styles.keys+[:original]).each do |style|
          path = rich_file.path(style)
          FileUtils.move path, File.join(File.dirname(path), new_filename)
        end
      end

      def cache_style_uris_and_save
        cache_style_uris
        self.save!
      end


      def rename_file!(version, new_filename)
        path = version.path
        FileUtils.move path, File.join(File.dirname(path), new_filename)
      end

      def check_content_type
        unless self.rich_file_content_type == 'folder'
          self.rich_file.instance_write(:content_type, MIME::Types.type_for(rich_file_file_name)[0].content_type)
          if !Rich.validate_mime_type(self.rich_file_content_type, self.simplified_type)
            self.errors[:base] << "'#{self.rich_file_file_name}' is not the right type."
          elsif self.simplified_type == 'all' && Rich.allowed_image_types.include?(self.rich_file_content_type)
            self.simplified_type = 'image'
          elsif self.simplified_type == 'all' && Rich.allowed_video_types.include?(self.rich_file_content_type)
            self.simplified_type = 'video'
          elsif self.simplified_type == 'all' && Rich.allowed_audio_types.include?(self.rich_file_content_type)
            self.simplified_type = 'audio'
          end
        end
      end

      def cache_style_uris
        uris = {}

        rich_file.styles.each do |style|
          uris[style[0]] = rich_file.url(style[0].to_sym, false)
        end

        # manualy add the original size
        uris["original"] = rich_file.url(:original, false)

        self.uri_cache = uris.to_json
      end

      # def check_content_type
      #   unless Rich.validate_mime_type(self.rich_file_content_type, self.simplified_type)
      #     self.errors[:base] << "'#{self.rich_file_file_name}' is not the right type."
      #   end
      # end

      def update_rich_file_attributes
        if rich_file.present? && rich_file_file_name_changed?
          self.rich_file_content_type = rich_file.file.content_type
          self.rich_file_file_size = rich_file.file.size
          self.rich_file_updated_at = Time.now
        end
      end

      def clear_uri_cache
        write_attribute(:uri_cache, nil)
      end


      def clean_file_name
        extension = File.extname(rich_file_file_name).gsub(/^\.+/, '')
        filename = rich_file_file_name.gsub(/\.#{extension}$/, '')

        filename = CGI::unescape(filename)

        extension = extension.downcase
        filename = filename.downcase.gsub(/[^a-z0-9]+/i, '-')

        self.rich_file.instance_write(:file_name, "#{filename}.#{extension}")
      end

      module ClassMethods

      end
    end
  end

  Rich::RichFile.send(:include, Backends::CarrierWave)
end

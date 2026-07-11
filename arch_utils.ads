-- Arch archive manager storing Z-compressed files
-- Copyright (C) by PragmAda Software Engineering
-- SPDX-License-Identifier: BSD-3-Clause
-- See https://spdx.org/licenses/
-- If you find this software useful, please let me know, either through
-- github.com/jrcarter or directly to pragmada@pragmada.x10hosting.com
--
-- Operations on Arch archive files
--
-- An archive <archive name> is modified by writing a new version of the archive in <archive name>.tmp
-- Once the new version of the archive is successfully written, <archive name> is deleted and <archive name>.tmp is renamed to
-- <archive name>. If an error is encountered in modifying the archive, the original archive will still exist
-- The order of files within the archive may change after modification
--
-- The Zlib header and checksum are checked for extracted files
-- If either is incorrect, the assumption is that the archive is invalid or corrupt, so processing stops immediately
--
-- An archive is a sequence of files
-- A file consists of a header followed by the Zlib-format compressed contents of the original file
-- The header contains the uncompressed and compressed sizes of the file and the file's simple name (without path)
--
with Ada.Containers.Indefinite_Vectors;

package Arch_Utils is
   package String_Lists is new Ada.Containers.Indefinite_Vectors (Index_Type => Positive, Element_Type => String);
   subtype String_List is String_Lists.Vector;

   -- If any operation fails or has issues, the failure or issues are described in Msg

   procedure Update (Arch_Name : in String; File : in String_List; Msg : out String_List; Directory : in String := "") with
      Pre => Directory = "" or else Directory (Directory'Last) in '/' | '\';
   -- Updates or adds the files in File from Directory to Arch_Name
   -- Creates Arch_Name if it doesn't exist

   procedure List (Arch_Name : in String; Content : out String_List; Msg : out String_List);
   -- Lists the files in Arch_Name in Content

   procedure Delete (Arch_Name : in String; File : in String_List; Msg : out String_List);
   -- Deletes the files in File from Arch_Name

   procedure Extract (Arch_Name : in String; File : in String_List; Msg : out String_List; Directory : in String := "") with
      Pre => Directory = "" or else Directory (Directory'Last) in '/' | '\';
   -- Extracts the files in File from Arch_Name to Directory (current directory if Directory is "")
   -- If File is empty, extracts all files
end Arch_Utils;

-- Command-line archive manager storing Z-compressed files
-- Copyright (C) by PragmAda Software Engineering
-- SPDX-License-Identifier: BSD-3-Clause
-- See https://spdx.org/licenses/
-- If you find this software useful, please let me know, either through
-- github.com/jrcarter or directly to pragmada@pragmada.x10hosting.com
--
-- Arch, an archive manager
--
--  Usage:
--     arch <command> <archive name> {<file name>} [-d <directory>]
--  where <command> is one of
--     u[pdate]  update or add given files to the archive from <directory>,
--               if given [default: current directory]
--     l[ist]    list the files in the archive
--     d[elete]  delete the given files from the archive
--     x[tract]  extract files from the archive [default: all files]
--               to <directory>, if given [default: current directory]
--  only the first character of the command is significant
--  except for u[pdate], the archive must exist
--
-- To create an archive, use u[pdate] with an <archive name> that doesn't exist
-- <file name>(s) are required for u[pdate] and d[elete], optional for x[tract], and ignored for l[ist]
-- <file name>(s) should be simple names, without path, and will be simplified if not
-- Added/updated files are read from <directory>, if given, or the current directory if not
-- Extracted files are written in <directory>, if given, or the current directory if not, and any existing files are silently
-- overwritten
-- <directory> is ignored for l[ist] and d[elete]
-- l[ist] lists the files in the archive in String "<" order of name, together with their (uncompressed) sizes in bytes
--
-- An archive is modified by writing a new version of the archive in <archive name>.tmp
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

with Ada.Command_Line;
with Ada.Containers.Indefinite_Vectors;
with Ada.Direct_IO;
with Ada.Directories;
with Ada.Text_IO;

procedure Arch is
   package Name_Lists is new Ada.Containers.Indefinite_Vectors (Index_Type => Positive, Element_Type => String);
   subtype Name_List is Name_Lists.Vector;

   type U64 is mod 2 ** 64;

   subtype File_Name_Length is Integer range 0 .. 2 ** 15 -1;

   type Header_Info (Name_Length : File_Name_Length) is record
      Compressed_Length : U64; -- Length of compressed data, including zlib header and Adler-32 checksum
      Original_Length   : U64; -- Length of the original, uncompressed file
      Name              : String (1 .. Name_Length); -- File name
   end record;

   type U8 is mod 2 ** 8;

   package U8_IO is new Ada.Direct_IO (Element_Type => U8);

   procedure Usage;
   -- Output usage information

   function File_Names return Name_List;
   -- Collects Arguments 3 .. Argument_Count into the result, which may be empty
   -- Duplicate Arguments only appear in the result once

   procedure Update (Arch_Name : in String; File : in Name_List);
   -- Updates or adds the files in File to Arch_Name

   procedure List (Arch_Name : in String);
   -- Lists the files in Arch_Name

   procedure Delete (Arch_Name : in String; File : in Name_List);
   -- Deletes the files in File from Arch_Name

   procedure Extract (Arch_Name : in String; File : in Name_List);
   -- Extracts the files in File from Arch_Name
   -- If File is empty, extracts all files

   use type U8_IO.File_Mode;

   function Next (File : in U8_IO.File_Type) return U64 with
      Pre => U8_IO.Is_Open (File) and then U8_IO.Mode (File) = U8_IO.In_File;
   -- Reads a U64 in little-endian format from File

   function Next (File : in U8_IO.File_Type) return File_Name_Length with
      Pre => U8_IO.Is_Open (File) and then U8_IO.Mode (File) = U8_IO.In_File;
   -- Reads a File_Name_Length in little-endian format from File

   function Next (File : in U8_IO.File_Type) return Header_Info with
      Pre => U8_IO.Is_Open (File) and then U8_IO.Mode (File) = U8_IO.In_File;
   -- Reads a Header_Info from File

   procedure Write (File : in U8_IO.File_Type; Value : in U64) with
      Pre => U8_IO.Is_Open (File) and then U8_IO.Mode (File) = U8_IO.Out_File;
   -- Writes Value in little-endian format to File

   procedure Write (File : in U8_IO.File_Type; Value : in File_Name_Length) with
      Pre => U8_IO.Is_Open (File) and then U8_IO.Mode (File) = U8_IO.Out_File;
   -- Writes Value in little-endian format to File

   procedure Write (File : in U8_IO.File_Type; Header : in Header_Info) with
      Pre => U8_IO.Is_Open (File) and then U8_IO.Mode (File) = U8_IO.Out_File;
   -- Writes Header to File

   procedure Copy (From : in U8_IO.File_Type; To : in U8_IO.File_Type; Count : in U64) with
      Pre => (U8_IO.Is_Open (From) and U8_IO.Is_Open (To) ) and then
             (U8_IO.Mode (From) = U8_IO.In_File and U8_IO.Mode (To) = U8_IO.Out_File);
   -- Reads Count bytes from From and writes them to To

   procedure Skip (File : in U8_IO.File_Type; Count : in U64) with
      Pre => U8_IO.Is_Open (File) and then U8_IO.Mode (File) = U8_IO.In_File,
      Inline;
   -- Skips Count bytes in File

   function Missing (Name : in String) return Boolean;
   -- If archive Name does not exist, outputs a message and returns True; otherwise, returns False

   procedure Usage is
      -- Empty
   begin -- Usage
      Ada.Text_IO.Put_Line (Item => "Usage:");
      Ada.Text_IO.Put_Line (Item => "   arch <command> <archive name> {<file name>} [-d <directory>]");
      Ada.Text_IO.Put_Line (Item => "where <command> is one of");
      Ada.Text_IO.Put_Line (Item => "   u[pdate]  update or add given files to the archive from <directory>,");
      Ada.Text_IO.Put_Line (Item => "             if given [default: current directory]");
      Ada.Text_IO.Put_Line (Item => "   l[ist]    list the files in the archive");
      Ada.Text_IO.Put_Line (Item => "   d[elete]  delete the given files from the archive");
      Ada.Text_IO.Put_Line (Item => "   x[tract]  extract files from the archive [default: all files]");
      Ada.Text_IO.Put_Line (Item => "             to <directory>, if given [default: current directory]");
      Ada.Text_IO.Put_Line (Item => "only the first character of the command is significant");
      Ada.Text_IO.Put_Line (Item => "except for u[pdate], the archive must exist");
   end Usage;

   Dir_Arg : constant String := (if Ada.Command_Line.Argument_Count > 3 and then
                                    Ada.Command_Line.Argument (Ada.Command_Line.Argument_Count - 1) = "-d"
                                 then
                                    Ada.Command_Line.Argument (Ada.Command_Line.Argument_Count)
                                 else
                                    "");
   Last_File : constant Natural := (if Dir_Arg = "" then Ada.Command_Line.Argument_Count
                                    else Ada.Command_Line.Argument_Count - 2);
   Dir_Sep   : constant String  := (if Ada.Directories.Current_Directory (1) = '/' then "/" else "\");
   Directory : constant String  := (if Dir_Arg = "" then ""
                                    else Dir_Arg & (if Dir_Arg (Dir_Arg'Last) = Dir_Sep (1) then "" else Dir_Sep) );

   function File_Names return Name_List is
      Result : Name_List;
   begin -- File_Names
      All_Names : for I in 3 .. Last_File loop
         Simplify : begin
            if not Result.Contains (Ada.Directories.Simple_Name (Ada.Command_Line.Argument (I) ) ) then
               Result.Append (New_Item => Ada.Directories.Simple_Name (Ada.Command_Line.Argument (I) ) );
            end if;
         exception -- Simplify
         when Ada.Directories.Name_Error =>
            Ada.Text_IO.Put_Line (Item => "Invalid file name " & Ada.Command_Line.Argument (I) & ": ignoring");
         end Simplify;
      end loop All_Names;

      return Result;
   end File_Names;

   procedure Update (Arch_Name : in String; File : in Name_List) is separate;

   procedure List (Arch_Name : in String) is separate;

   procedure Delete (Arch_Name : in String; File : in Name_List) is separate;

   procedure Extract (Arch_Name : in String; File : in Name_List) is separate;

   function Next (File : in U8_IO.File_Type) return U64 is
      Byte   : U8;
      Result : U64 := 0;
      Mult   : U64 := 1;
   begin -- Next
      All_Bytes : for I in 1 .. 8 loop
         U8_IO.Read (File => File, Item => Byte);
         Result := Result + Mult * U64 (Byte);
         Mult := 256 * Mult;
      end loop All_Bytes;

      return Result;
   end Next;

   function Next (File : in U8_IO.File_Type) return File_Name_Length is
      Byte   : U8;
      Result : File_Name_Length;
   begin -- Next
      U8_IO.Read (File => File, Item => Byte);
      Result := Integer (Byte);
      U8_IO.Read (File => File, Item => Byte);
      Result := Result + 256 * Integer (Byte);

      return Result;
   end Next;

   function Next (File : in U8_IO.File_Type) return Header_Info is
      C_Len : U64              renames Next (File);
      O_Len : U64              renames Next (File);
      N_Len : File_Name_Length renames Next (File);

      Result : Header_Info (Name_Length => N_Len);
      Byte   : U8;
   begin -- Next
      Result.Compressed_Length := C_Len;
      Result.Original_Length := O_Len;

      Read_Name : for I in Result.Name'Range loop
         U8_IO.Read (File => File, Item => Byte);
         Result.Name (I) := Character'Val (Byte);
      end loop Read_Name;

      return Result;
   end Next;

   procedure Write (File : in U8_IO.File_Type; Value : in U64) is
      Item : U64 := Value;
   begin -- Write
      All_Bytes : for I in 1 .. 8 loop
         U8_IO.Write (File => File, Item => U8 (Item rem 256) );
         Item := Item / 256;
      end loop All_Bytes;
   end Write;

   procedure Write (File : in U8_IO.File_Type; Value : in File_Name_Length) is
      Item : File_Name_Length := Value;
   begin -- Write
      All_Bytes : for I in 1 .. 2 loop
         U8_IO.Write (File => File, Item => U8 (Item rem 256) );
         Item := Item / 256;
      end loop All_Bytes;
   end Write;

   procedure Write (File : in U8_IO.File_Type; Header : in Header_Info) is
      -- Empty
   begin -- Write
      Write (File => File, Value => Header.Compressed_Length);
      Write (File => File, Value => Header.Original_Length);
      Write (File => File, Value => Header.Name_Length);

      Write_Name : for I in Header.Name'Range loop
         U8_IO.Write (File => File, Item => Character'Pos (Header.Name (I) ) );
      end loop Write_Name;
   end Write;

   procedure Copy (From : in U8_IO.File_Type; To : in U8_IO.File_Type; Count : in U64) is
      Byte : U8;
   begin -- Copy
      All_Bytes : for I in 1 .. Count loop
         U8_IO.Read (File => From, Item => Byte);
         U8_IO.Write (File => To, Item => Byte);
      end loop All_Bytes;
   end Copy;

   procedure Skip (File : in U8_IO.File_Type; Count : in U64) is
      -- Empty
   begin -- Skip
      U8_IO.Set_Index (File => File, To => U8_IO.Count (U64 (U8_IO.Index (File) ) + Count) );
   end Skip;

   function Missing (Name : in String) return Boolean is
      -- Empty
   begin -- Missing
      if not Ada.Directories.Exists (Name) then
         Ada.Text_IO.Put_Line (Item => "Archive " & Name & " does not exist");

         return True;
      end if;

      return False;
   end Missing;
begin -- Arch
  if Ada.Command_Line.Argument_Count < 2 or else (Ada.Command_Line.Argument (1) = "" or Ada.Command_Line.Argument (2) = "") then
      Usage;

      return;
   end if;

   Get_Args : declare
      Command   : String    renames Ada.Command_Line.Argument (1);
      Arch_Name : String    renames Ada.Command_Line.Argument (2);
      File      : Name_List renames File_Names;
   begin -- Get_Args
      case Command (1) is
      when 'u' =>
         Update (Arch_Name => Arch_Name, File => File);
      when 'l' =>
         List (Arch_Name => Arch_Name);
      when 'd' =>
         Delete (Arch_Name => Arch_Name, File => File);
      when 'x' =>
         Extract (Arch_Name => Arch_Name, File => File);
      when others =>
         Usage;
      end case;
   end Get_Args;
end Arch;

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
with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;
with Arch_Utils;

procedure Arch is
   procedure Usage;
   -- Output usage information

   function File_Names return Arch_Utils.String_List;
   -- Collects Arguments 3 .. Last_File into the result, which may be empty
   -- Duplicate Arguments only appear in the result once

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

   function File_Names return Arch_Utils.String_List is
      Result : Arch_Utils.String_List;
   begin -- File_Names
      All_Names : for I in 3 .. Last_File loop
         Simplify : begin
            Result.Append (New_Item => Ada.Directories.Simple_Name (Ada.Command_Line.Argument (I) ) );
         exception -- Simplify
         when Ada.Directories.Name_Error => -- Invalid name; ignore
            null;
         end Simplify;
      end loop All_Names;

      return Result;
   end File_Names;
begin -- Arch
  if Ada.Command_Line.Argument_Count < 2 or else (Ada.Command_Line.Argument (1) = "" or Ada.Command_Line.Argument (2) = "") then
      Usage;

      return;
   end if;

   Get_Args : declare
      Command   : String      renames Ada.Command_Line.Argument (1);
      Arch_Name : String      renames Ada.Command_Line.Argument (2);
      File      : Arch_Utils.String_List renames File_Names;
      Msg       : Arch_Utils.String_List;
      Content   : Arch_Utils.String_List;
   begin -- Get_Args
      case Command (1) is
      when 'u' =>
         Arch_Utils.Update (Arch_Name => Arch_Name, File => File, Msg => Msg, Directory => Directory);
      when 'l' =>
         Arch_Utils.List (Arch_Name => Arch_Name, Content => Content, Msg => Msg);

         Dump_Content : for I in 1 .. Content.Last_Index loop
            Ada.Text_IO.Put_Line (Item => Content.Element (I) );
         end loop Dump_Content;
      when 'd' =>
         Arch_Utils.Delete (Arch_Name => Arch_Name, File => File, Msg => Msg);
      when 'x' =>
         Arch_Utils.Extract (Arch_Name => Arch_Name, File => File, Msg => Msg, Directory => Directory);
      when others =>
         Usage;
      end case;

      Dump_Msg : for I in 1 .. Msg.Last_Index loop
         Ada.Text_IO.Put_Line (Item => Msg.Element (I) );
      end loop Dump_Msg;
   end Get_Args;
end Arch;

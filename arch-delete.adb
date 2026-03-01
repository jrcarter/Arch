-- Command-line archive manager storing Z-compressed files
-- Copyright (C) by PragmAda Software Engineering
-- SPDX-License-Identifier: BSD-3-Clause
-- See https://spdx.org/licenses/
-- If you find this software useful, please let me know, either through
-- github.com/jrcarter or directly to pragmada@pragmada.x10hosting.com
--
separate (Arch)
procedure Delete (Arch_Name : in String; File : in Name_List) is
   Temp_Name : constant String := Arch_Name & ".tmp";

   Curr  : U8_IO.File_Type;
   Temp  : U8_IO.File_Type;
   Found : Name_List;
begin -- Delete
   if Missing (Arch_Name) then
      return;
   end if;

   if File.Last_Index = 0 then
      Ada.Text_IO.Put_Line (Item => "No files given");

      return;
   end if;

   U8_IO.Open (File => Curr, Mode => U8_IO.In_File, Name => Arch_Name);
   U8_IO.Create (File => Temp, Mode => U8_IO.Out_File, Name => Temp_Name);

   Copy_Kept : loop
      exit Copy_Kept when U8_IO.End_Of_File (Curr);

      One_File : declare
         Header : constant Header_Info := Next (Curr);
      begin -- One_File
         if File.Contains (Header.Name) then -- Delete this file
            Skip (File => Curr, Count => Header.Compressed_Length);
            Found.Append (New_Item => Header.Name);
         else -- Keep this file
            Write (File => Temp, Header => Header);
            Copy (From => Curr, To => Temp, Count => Header.Compressed_Length);
         end if;
      end One_File;
   end loop Copy_Kept;

   U8_IO.Close (File => Curr);
   U8_IO.Close (File => Temp);
   Ada.Directories.Delete_File (Name => Arch_Name);
   Ada.Directories.Rename (Old_Name => Temp_Name, New_Name => Arch_Name);

   Report_Missing : for I in 1 .. File.Last_Index loop
      if not Found.Contains (File.Element (I) ) then
         Ada.Text_IO.Put_Line (Item => "File " & File.Element (I) & " is not in " & Arch_Name & "; ignoring");
      end if;
   end loop Report_Missing;
end Delete;

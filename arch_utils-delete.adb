-- Arch archive manager storing Z-compressed files
-- Copyright (C) by PragmAda Software Engineering
-- SPDX-License-Identifier: BSD-3-Clause
-- See https://spdx.org/licenses/
-- If you find this software useful, please let me know, either through
-- github.com/jrcarter or directly to pragmada@pragmada.x10hosting.com
--
separate (Arch_Utils)
procedure Delete (Arch_Name : in String; File : in String_List; Msg : out String_List) is
   Temp_Name : constant String := Arch_Name & ".tmp";

   Missing : Boolean;
   Curr    : U8_IO.File_Type;
   Temp    : U8_IO.File_Type;
   Found   : String_List;
   Name    : String_List;
begin -- Delete
   Check_Existing (Arch_Name => Arch_Name, Missing => Missing, Msg => Msg);

   if Missing then
      return;
   end if;

   if File.Last_Index = 0 then
      Msg.Append (New_Item => "No files given");

      return;
   end if;

   Name := Simplified (File, Msg);
   U8_IO.Open (File => Curr, Mode => U8_IO.In_File, Name => Arch_Name);
   U8_IO.Create (File => Temp, Mode => U8_IO.Out_File, Name => Temp_Name);

   Copy_Kept : loop
      exit Copy_Kept when U8_IO.End_Of_File (Curr);

      One_File : declare
         Header : constant Header_Info := Next (Curr);
      begin -- One_File
         if Name.Contains (Header.Name) then -- Delete this file
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

   Report_Missing : for I in 1 .. Name.Last_Index loop
      if not Found.Contains (Name.Element (I) ) then
         Msg.Append (New_Item => "File " & Name.Element (I) & " is not in " & Arch_Name & "; ignoring");
      end if;
   end loop Report_Missing;
end Delete;

-- Command-line archive manager storing Z-compressed files
-- Copyright (C) by PragmAda Software Engineering
-- SPDX-License-Identifier: BSD-3-Clause
-- See https://spdx.org/licenses/
-- If you find this software useful, please let me know, either through
-- github.com/jrcarter or directly to pragmada@pragmada.x10hosting.com
--
with PragmARC.Images;

separate (Arch)
procedure List (Arch_Name : in String) is
   package Header_Lists is new Ada.Containers.Indefinite_Vectors (Index_Type => Positive, Element_Type => Header_Info);

   function "<" (Left : in Header_Info; Right : in Header_Info) return Boolean is
      (Left.Name < Right.Name);

   package Sorting is new Header_Lists.Generic_Sorting;

   function Image is new PragmARC.Images.Modular_Image (Number => U64);

   Archive  : U8_IO.File_Type;
   List     : Header_Lists.Vector;
   Max_Name : Natural := 0;
   Max_Size : Natural := 0;
begin -- List
   if Missing (Arch_Name) then
      return;
   end if;

   U8_IO.Open (File => Archive, Mode => U8_IO.In_File, Name => Arch_Name);

   All_Files : loop
      exit All_Files when U8_IO.End_Of_File (Archive);

      One_File : declare
         Header : constant Header_Info := Next (Archive);
      begin -- One_File
         List.Append (New_Item => Header);
         Skip (File => Archive, Count => Header.Compressed_Length);
      end One_File;
   end loop All_Files;

   U8_IO.Close (File => Archive);

   Sorting.Sort (Container => List);

   Find_Max : for I in 1 .. List.Last_Index loop
      One_Header : declare
         Header : constant Header_Info := List.Element (I);
      begin -- One_Header
         Max_Name := Integer'Max (Max_Name, Header.Name_Length);
         Max_Size := Integer'Max (Max_Size, Header.Original_Length'Image'Length);
      end One_Header;
   end loop Find_Max;

   Print : for I in 1 .. List.Last_Index loop
      One_Line : declare
         Header : constant Header_Info := List.Element (I);
      begin -- One_Line
         Ada.Text_IO.Put_Line
            (Item => Header.Name & Image (Header.Original_Length, Width => Max_Size + Max_Name - Header.Name_Length) );
      end One_Line;
   end loop Print;
end List;

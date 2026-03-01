-- Command-line archive manager storing Z-compressed files
-- Copyright (C) by PragmAda Software Engineering
-- SPDX-License-Identifier: BSD-3-Clause
-- See https://spdx.org/licenses/
-- If you find this software useful, please let me know, either through
-- github.com/jrcarter or directly to pragmada@pragmada.x10hosting.com
--
with Ada.Containers.Vectors;
with Z_Compression;

separate (Arch)
procedure Update (Arch_Name : in String; File : in Name_List) is
   type Position is range 1 .. 2 ** 63 - 1;

   package Byte_Lists is new Ada.Containers.Vectors (Index_Type => Position, Element_Type => U8);
   subtype Byte_List is Byte_Lists.Vector;

   procedure Compress (Name : in String; Byte : in out Byte_List);
   -- Clears Byte, then compresses the contents of Name

   procedure Write (File : in U8_IO.File_Type; Byte : in Byte_List) with
      Pre => U8_IO.Is_Open (File) and then U8_IO.Mode (File) = U8_IO.Out_File;
   -- Writes the bytes in Byte to file

   procedure Compress (Name : in String; Byte : in out Byte_List) is
      File : U8_IO.File_Type;

      function Out_Of_Data return Boolean is
         (U8_IO.End_Of_File (File) );

      function Next return Z_Compression.Byte_Value is
         Byte : U8;
      begin -- Next
         if U8_IO.End_Of_File (File) then
            raise Z_Compression.Data_Exhausted;
         end if;

         U8_IO.Read (File => File, Item => Byte);

         return Z_Compression.Byte_Value (Byte);
      end Next;

      procedure Put (Value : in Z_Compression.Byte_Value) is
         -- Empty
      begin -- Put
         Byte.Append (New_Item => U8 (Value) );
      end Put;

      procedure Compress is new Z_Compression.Compress (Out_Of_Data => Out_Of_Data, Next => Next, Put => Put);
   begin -- Compress
      Byte.Clear;
      U8_IO.Open (File => File, Mode => U8_IO.In_File, Name => Name);
      Compress (Method => Z_Compression.Deflate_3);
      U8_IO.Close (File => File);
   end Compress;

   procedure Write (File : in U8_IO.File_Type; Byte : in Byte_List) is
      -- Empty
   begin -- Write
      All_Bytes : for I in 1 .. Byte.Last_Index loop
         U8_IO.Write (File => File, Item => Byte.Element (I) );
      end loop All_Bytes;
   end Write;

   Temp_Name : constant String := Arch_Name & ".tmp";

   Curr : U8_IO.File_Type;
   Temp : U8_IO.File_Type;
begin -- Update
   if File.Is_Empty then
      Ada.Text_IO.Put_Line (Item => "No files given");

      return;
   end if;

   U8_IO.Create (File => Temp, Mode => U8_IO.Out_File, Name => Temp_Name);

   if Ada.Directories.Exists (Arch_Name) then
      U8_IO.Open (File => Curr, Mode => U8_IO.In_File, Name => Arch_Name);

      Copy_Unchanged : loop
         exit Copy_Unchanged when U8_IO.End_Of_File (Curr);

         Check_One : declare
            Header : constant Header_Info := Next (Curr);
         begin -- Check_One
            if File.Contains (Header.Name) then -- To be updated
               Skip (File => Curr, Count => Header.Compressed_Length);
            else -- Unchanged
               Write (File => Temp, Header => Header);
               Copy (From => Curr, To => Temp, Count => Header.Compressed_Length);
            end if;
         end Check_One;
      end loop Copy_Unchanged;

      U8_IO.Close (File => Curr);
   end if;

   New_Files : for I in 1 .. File.Last_Index loop
      Make_Header : declare
         Name   : String renames File.Element (I);
         Simple : String renames Ada.Directories.Simple_Name (Name);

         Header     : Header_Info (Name_Length => Simple'Length);
         Compressed : Byte_List;
      begin -- Make_Header
         if not Ada.Directories.Exists (Name) then
            Ada.Text_IO.Put_Line (Item => "File " & Name & " does not exist; ignoring");
         else
            Header.Original_Length := U64 (Ada.Directories.Size (Name) );
            Header.Name := Simple;
            Compress (Name => Name, Byte => Compressed);
            Header.Compressed_Length := U64 (Compressed.Last_Index);
            Write (File => Temp, Header => Header);
            Write (File => Temp, Byte => Compressed);
         end if;
      end Make_Header;
   end loop New_Files;

   U8_IO.Close (File => Temp);

   if Ada.Directories.Exists (Arch_Name) then
      Ada.Directories.Delete_File (Name => Arch_Name);
   end if;

   Ada.Directories.Rename (Old_Name => Temp_Name, New_Name => Arch_Name);
end Update;

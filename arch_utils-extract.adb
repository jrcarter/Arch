-- Arch archive manager storing Z-compressed files
-- Copyright (C) by PragmAda Software Engineering
-- SPDX-License-Identifier: BSD-3-Clause
-- See https://spdx.org/licenses/
-- If you find this software useful, please let me know, either through
-- github.com/jrcarter or directly to pragmada@pragmada.x10hosting.com
--
with Ada.Exceptions;
with Adler_32_Checksums;
with Z_Compression;

separate (Arch_Utils)
procedure Extract (Arch_Name : in String; File : in String_List; Msg : out String_List; Directory : in String := "") is
   To_Read  : U64;
   Num_Read : U64;

   function Out_Of_Data return Boolean is
      (Num_Read >= To_Read);

   function Next return Z_Compression.Byte_Value;

   procedure Put (Value : in Z_Compression.Byte_Value);

   procedure Decompress is new Z_Compression.Decompress (Out_Of_Data => Out_Of_Data, Next => Next, Put => Put);

   First   : Boolean;
   Buffer  : Z_Compression.Byte_Buffer (1 .. 4);
   Archive : U8_IO.File_Type;
   Extrac  : U8_IO.File_Type;
   Adler   : Adler_32_Checksums.Checksum_Info;

   function Next return Z_Compression.Byte_Value is
      Byte   : U8;
      Result : Z_Compression.Byte_Value;

      use type Z_Compression.Byte_Buffer;
   begin -- Next
      if First then
         First := False;
         U8_IO.Read (File => Archive, Item => Byte);

         if Byte /= 16#78# then -- Invalid Zlib header
            raise Z_Compression.Invalid_Data with "Invalid archive " & Arch_Name & ": invalid zlib header";
         end if;

         U8_IO.Read (File => Archive, Item => Byte); -- Header 2nd byte

         Fill : for I in Buffer'Range loop
            U8_IO.Read (File => Archive, Item => Byte);
            Buffer (I) := Z_Compression.Byte_Value (Byte);
         end loop Fill;

         Num_Read := 6;
      end if;

      if Out_Of_Data then
         raise Z_Compression.Data_Exhausted;
      end if;

      Result := Buffer (1);
      U8_IO.Read (File => Archive, Item => Byte);
      Num_Read := Num_Read + 1;
      Buffer := Buffer (2 .. 4) & Z_Compression.Byte_Value (Byte);

      return Result;
   end Next;

   procedure Put (Value : in Z_Compression.Byte_Value) is
      -- Empty
   begin -- Put
      Adler_32_Checksums.Update (Info => Adler, Byte => Value);
      U8_IO.Write (File => Extrac, Item => U8 (Value) );
   end Put;

   Missing : Boolean;
   Name    : String_List;
   Found   : String_List;
begin -- Extract
   Check_Existing (Arch_Name => Arch_Name, Missing => Missing, Msg => Msg);

   if Missing then
      return;
   end if;

   Name := Simplified (File, Msg);
   U8_IO.Open (File => Archive, Mode => U8_IO.In_File, Name => Arch_Name);

   All_Files : loop
      exit All_Files when U8_IO.End_Of_File (Archive);

      One_File : declare
         Header : constant Header_Info := Next (Archive);

         Checksum : Adler_32_Checksums.Checksum_List;

         use type Adler_32_Checksums.Checksum_List;
      begin -- One_File
         if not Name.Is_Empty and not Name.Contains (Header.Name) then -- Skip this file
            Skip (File => Archive, Count => Header.Compressed_Length);
         else -- Extract this file
            Found.Append (New_Item => Header.Name);
            To_Read := Header.Compressed_Length;
            Num_Read := 0;
            First := True;

            Create : begin
               U8_IO.Create (File => Extrac, Mode => U8_IO.Out_File, Name => Directory & Header.Name);
               Adler_32_Checksums.Reset (Info => Adler);
               Decompress;
               U8_IO.Close (File => Extrac);
               Checksum := Adler_32_Checksums.Checksum (Adler);

               if Checksum /= Adler_32_Checksums.Checksum_List (Buffer) then -- Invalid checksum
                  Msg.Append (New_Item => "Invalid archive " & Arch_Name & ": invalid checksum for " & Header.Name);

                  return;
               end if;
            exception -- Create
            when others =>
               Msg.Append (New_Item => "Cannot create file " & Directory & Header.Name);
               Skip (File => Archive, Count => Header.Compressed_Length);
            end Create;
         end if;
      end One_File;
   end loop All_Files;

   U8_IO.Close (File => Archive);

   Report_Missing : for I in 1 .. Name.Last_Index loop
      if not Found.Contains (Name.Element (I) ) then
         Msg.Append (New_Item => "File " & Name.Element (I) & " is not in " & Arch_Name & "; ignoring");
      end if;
   end loop Report_Missing;
exception -- Extract
when E : Z_Compression.Invalid_Data =>
   Msg.Append (New_Item => Ada.Exceptions.Exception_Message (E) );
end Extract;

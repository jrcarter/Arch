-- Arch archive manager storing Z-compressed files
-- Copyright (C) by PragmAda Software Engineering
-- SPDX-License-Identifier: BSD-3-Clause
-- See https://spdx.org/licenses/
-- If you find this software useful, please let me know, either through
-- github.com/jrcarter or directly to pragmada@pragmada.x10hosting.com
--
with Ada.Directories;
with Ada.Direct_IO;

package body Arch_Utils is
   type U64 is mod 2 ** 64;

   subtype File_Name_Length is Integer range 0 .. 2 ** 15 -1;

   type Header_Info (Name_Length : File_Name_Length) is record
      Compressed_Length : U64; -- Length of compressed data, including zlib header and Adler-32 checksum
      Original_Length   : U64; -- Length of the original, uncompressed file
      Name              : String (1 .. Name_Length); -- File name
   end record;

   type U8 is mod 2 ** 8;

   package U8_IO is new Ada.Direct_IO (Element_Type => U8);

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

   procedure Check_Existing (Arch_Name : in String; Missing : out Boolean; Msg : in out String_List);
   -- If a file named Arch_Name exists, sets Missing to False and leaves Msg unchanged
   -- Otherwise, sets Missing to True and appends a message to Msg

   function Simplified (File : in String_List; Msg : in out String_List) return String_List;
   -- Makes the file names in File simple names and eliminates duplicates

   procedure Update (Arch_Name : in String; File : in String_List; Msg : out String_List; Directory : in String := "")
   is separate;

   procedure List (Arch_Name : in String; Content : out String_List; Msg : out String_List) is separate;

   procedure Delete (Arch_Name : in String; File : in String_List; Msg : out String_List) is separate;

   procedure Extract (Arch_Name : in String; File : in String_List; Msg : out String_List; Directory : in String := "")
   is separate;

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

   procedure Check_Existing (Arch_Name : in String; Missing : out Boolean; Msg : in out String_List) is
      -- Empty
   begin -- Check_Existing
      Missing := not Ada.Directories.Exists (Arch_Name);

      if Missing then
         Msg.Append (New_Item => "Archive " & Arch_Name & " does not exist");
      end if;
   end Check_Existing;

   function Simplified (File : in String_List; Msg : in out String_List) return String_List is
      Result : String_List;
   begin -- Simplified
      All_Names : for I in 1 .. File.Last_Index loop
         Simplify : begin
            if not Result.Contains (Ada.Directories.Simple_Name (File.Element (I) ) ) then
               Result.Append (New_Item => Ada.Directories.Simple_Name (File.Element (I) ) );
            end if;
         exception -- Simplify
         when Ada.Directories.Name_Error =>
            Msg.Append (New_Item => "Invalid file name " & File.Element (I) & ": ignoring");
         end Simplify;
      end loop All_Names;

      return Result;
   end Simplified;
end Arch_Utils;

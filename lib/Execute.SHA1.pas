unit Execute.SHA1;

interface
{-$DEFINE LOG}
{$LEGACYIFEND OFF}
uses
{$IFDEF LOG}Winapi.Windows,{$ENDIF}
  System.Classes,
  System.SysUtils,
  Execute.UTF8.Utils;
{$R-,Q-}
type
  TSHA1Digest = record
  private
    Size : Integer;
    Hash : array[0..4] of Cardinal; // 20 bytes
    Index: Integer;
    Block: array[0..63] of Byte;
    procedure ProcessBlock;
    procedure Finalize;
  public
    procedure Init;
    procedure Update(Data: Pointer; Len: Integer);
    procedure AddChar(Ch: AnsiChar);
    function GetDigest: TBytes;
    function ToHex: string;
    function ToHex8: UTF8String;
  end;

function SHA1(Data: Pointer; Len: Integer): UTF8String;
function SHA1Hex(const Str: UTF8String): string;
function SHA1HexA(const Str: AnsiString): string;
function SHA1Str(const Str: UTF8String): UTF8String;
function SHA1FromFile(const AFileName: string): UTF8String;

function HMAC_SHA1(const Key, Value: TBytes): TBytes;
function HMAC_SHA1_Hexa(const Key, Value: UTF8String): UTF8String;
function HMAC_SHA1_UTF8(const Key, Value: UTF8String): UTF8String;

implementation

function XorBytes(const Src: TBytes; Value: Byte): TBytes;
var
  Len  : Integer;
  Index: Integer;
begin
  SetLength(Result, 64);
  Len := Length(Src);
  if Len > 64 then
    Len := 64
  else
    FillChar(Result[Len], 64 - Len, Value);
  for Index := 0 to Len - 1 do
  begin
    Result[Index] := Src[Index] xor Value;
  end;
end;

function HMAC_SHA1(const Key, Value: TBytes): TBytes;
var
  opad: TBytes;
  ipad: TBytes;
  sha1: TSHA1Digest;
begin
  opad := XorBytes(key, $5C);
  ipad := XorBytes(key, $36);
// Result := SHA1(opad + SHA1(ipad + Value))
  sha1.Init;
  sha1.Update(Pointer(ipad), Length(ipad));
  sha1.Update(Pointer(Value), Length(Value));
  Result := sha1.GetDigest;
  sha1.Init;
  sha1.Update(Pointer(opad), Length(opad));
  sha1.Update(Pointer(Result), Length(Result));
  Result := sha1.GetDigest;
end;

function HMAC_SHA1_Hexa(const Key, Value: UTF8String): UTF8String;
var
  opad: TBytes;
  ipad: TBytes;
  sha1: TSHA1Digest;
begin
  var bKey := TEncoding.UTF8.GetBytes(Key);
  opad := XorBytes(bkey, $5C);
  ipad := XorBytes(bkey, $36);
// Result := SHA1(opad + SHA1(ipad + Value))
  sha1.Init;
  sha1.Update(Pointer(ipad), Length(ipad));
  sha1.Update(Pointer(Value), Length(Value));
  var sha := sha1.GetDigest;
  sha1.Init;
  sha1.Update(Pointer(opad), Length(opad));
  sha1.Update(Pointer(sha), Length(sha));
  Result := sha1.ToHex8;
end;

function HMAC_SHA1_UTF8(const Key, Value: UTF8String): UTF8String;
begin
  Result := Base64Encode(HMAC_SHA1(TEncoding.UTF8.GetBytes(Key), TEncoding.UTF8.GetBytes(Value)));
end;

function SHA1(Data: Pointer; Len: Integer): UTF8String;
var
  Digest: TSHA1Digest;
  Value : TBytes;
begin
  Digest.Init;
  Digest.Update(Data, Len);
  Value := Digest.GetDigest;
  Result := Base64Encode(PByte(Value), Length(Value));
end;

function SHA1Hex(const Str: UTF8String): string;
var
  SHA1: TSHA1Digest;
begin
  SHA1.Init;
  SHA1.Update(Pointer(Str), Length(Str));
  Result := SHA1.ToHex();
end;

function SHA1HexA(const Str: AnsiString): string;
var
  SHA1: TSHA1Digest;
begin
  SHA1.Init;
  SHA1.Update(Pointer(Str), Length(Str));
  Result := SHA1.ToHex();
end;

function SHA1Str(const Str: UTF8String): UTF8String;
begin
  Result := SHA1(PByte(Str), Length(Str));
end;

function SHA1FromFile(const AFileName: string): UTF8String;
var
  Stm: TMemoryStream;
begin
  Stm := TMemoryStream.Create;
  try
    Stm.LoadFromFile(AFileName);
    Result := SHA1(Stm.Memory, Stm.Size);
  finally
    Stm.Free;
  end;
end;

{ TSHA1Digest }

procedure TSHA1Digest.Init;
begin
{$IFDEF LOG}AllocConsole; WriteLn('<SHA1>');{$ENDIF}
  FillChar(Self, SizeOf(Self), 0);
  Hash[0] := $67452301;
  Hash[1] := $EFCDAB89;
  Hash[2] := $98BADCFE;
  Hash[3] := $10325476;
  Hash[4] := $C3D2E1F0;
end;

function SHA1CircularShift(bits, data: Cardinal): Cardinal;
begin
  Result := (data shl bits) or (data shr (32 - bits));
end;

procedure TSHA1Digest.ProcessBlock;
const
  K: array[0..3] of Cardinal = ($5A827999, $6ED9EBA1, $8F1BBCDC, $CA62C1D6);
var
  W: array[0..79] of Cardinal;
  t: Integer;
  index: Integer;
  A, B, C, D, E: Cardinal;
  temp: Cardinal;
begin
 // Initialize the first 16 words in the array W
  for t := 0 to 15 do begin
    index := 4 * t;
    W[t] := Block[index] shl 24
      or Block[index + 1] shl 16
      or Block[index + 2] shl 8
      or Block[index + 3];
  end;
  for t := 16 to 79 do begin
    W[t] := SHA1CircularShift(1, W[t - 3] xor W[t - 8] xor W[t - 14] xor W[t - 16]);
  end;
  A := Hash[0];
  B := Hash[1];
  C := Hash[2];
  D := Hash[3];
  E := Hash[4];
  for t := 0 to 19 do begin
    temp := SHA1CircularShift(5, A) + ((B and C) or ((not B) and D)) + E + W[t] + K[0];
    E := D;
    D := C;
    C := SHA1CircularShift(30, B);
    B := A;
    A := temp;
  end;
  for t := 20 to 39 do begin
    temp := SHA1CircularShift(5, A) + (B xor C xor D) + E + W[t] + K[1];
    E := D;
    D := C;
    C := SHA1CircularShift(30, B);
    B := A;
    A := temp;
  end;
  for t := 40 to 59 do begin
    temp := SHA1CircularShift(5, A) + ((B and C) or (B and D) or (C and D)) + E + W[t] + K[2];
    E := D;
    D := C;
    C := SHA1CircularShift(30, B);
    B := A;
    A := temp;
  end;
  for t := 60 to 79 do begin
    temp := SHA1CircularShift(5, A) + (B xor C xor D) + E + W[t] + K[3];
    E := D;
    D := C;
    C := SHA1CircularShift(30, B);
    B := A;
    A := temp;
  end;
  Inc(Hash[0], A);
  Inc(Hash[1], B);
  Inc(Hash[2], C);
  Inc(Hash[3], D);
  Inc(Hash[4], E);
  Self.Index := 0;
end;

function TSHA1Digest.ToHex: string;
const
  HX: array[0..$F] of Char = '0123456789abcdef';
var
  Hash: TBytes;
  Index: Integer;
begin
  Hash := GetDigest;
  SetLength(Result, 2 * Length(Hash));
  for Index := 0 to Length(Hash) - 1 do
  begin
    Result[2 * Index + 1] := HX[Hash[Index] shr 4];
    Result[2 * Index + 2] := HX[Hash[Index] and $F];
  end;
end;

function TSHA1Digest.ToHex8: UTF8String;
const
  HX: array[0..$F] of AnsiChar = '0123456789abcdef';
var
  Hash: TBytes;
  Index: Integer;
begin
  Hash := GetDigest;
  SetLength(Result, 2 * Length(Hash));
  for Index := 0 to Length(Hash) - 1 do
  begin
    Result[2 * Index + 1] := HX[Hash[Index] shr 4];
    Result[2 * Index + 2] := HX[Hash[Index] and $F];
  end;
end;

procedure TSHA1Digest.Update(Data: Pointer; Len: Integer);
var
  i: Integer;
  s: PByte;
begin
{$IFDEF LOG}Write(Copy(string(PAnsiChar(Data)), 1, Len));{$ENDIF}
  s := Data;
  Inc(Size, Len);
{$IF TRUE}
  if Index > 0 then
  begin
    i := 64 - Index;
    if i > Len then
    begin
      Move(s^, Block[Index], Len);
      Inc(Index, Len);
      Exit;
    end;
    Move(s^, Block[Index], i);
    Inc(s, i);
    Dec(Len, i);
    ProcessBlock;
  end;
  while Len >= 64 do
  begin
    Move(s^, Block[0], 64);
    ProcessBlock;
    Inc(s, 64);
    Dec(Len, 64);
  end;
  Index := Len;
  if Len > 0 then
    Move(s^, Block[0], Len);
{$ELSE}
  for i := 0 to Len - 1 do
  begin
    Block[Index] := s[i];
    Inc(Index);
    if Index = 64 then
      ProcessBlock();
  end;
{$ENDIF}
end;

procedure TSHA1Digest.AddChar(Ch: AnsiChar);
begin
{$IFDEF LOG}Write(Ch);{$ENDIF}
  Block[Index] := Ord(Ch);
  Inc(Size);
  Inc(Index);
  if Index = 64 then
    ProcessBlock();
end;

procedure TSHA1Digest.Finalize;
var
  i: Integer;
begin
{$IFDEF LOG}WriteLn('</SHA1>');{$ENDIF}
  i := Index;
  Block[i] := $80;
  Inc(i);
  if i > 56 then
  begin
    FillChar(Block[i], 64 - i, 0);
    Index := 64;
    ProcessBlock();
    FillChar(Block[0], 56, 0);
  end else begin
    FillChar(Block[i], 56 - i, 0);
  end;
  Index := 56;
 // Store the message length as the last 8 bytes
  Block[56] := 0;
  Block[57] := 0;
  Block[58] := 0;
  Block[59] := Size shr 29;
  Block[60] := Size shr 21;
  Block[61] := Size shr 13;
  Block[62] := Size shr 5;
  Block[63] := Size shl 3;
  ProcessBlock();
  Size := 0;
end;

function TSHA1Digest.GetDigest: TBytes;
var
  i: Integer;
begin
  Finalize;
  SetLength(Result, 20);
  for i := 0 to 19 do
  begin
    Result[i] := Byte(Hash[i shr 2] shr (8 * (3 - (i and 3))));
  end;
end;

initialization
{$IFDEF DEBUG}
  Assert(SHA1Hex('Wikipédia, l''encyclopédie libre et gratuite') = '6153a6fa0e4880d9b8d0be4720f78e895265d0a9');
  Assert(SHA1Hex(UTF8String(StringOfChar('A', 66))) = 'eddee92010936db2c45d2c9f5fdd2726fcd28789');
  Assert(SHA1Hex('Wikipédia, l''encyclopédie libre et gratuitE') = '11f453355b28e1158d4e516a2d3edf96b3450406');
  Assert(SHA1Hex('') = 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
{$ENDIF}
end.

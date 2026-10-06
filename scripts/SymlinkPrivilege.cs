using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace RepoInstaller
{
    public static class SymlinkPrivilege
    {
        private const string Right = "SeCreateSymbolicLinkPrivilege";

        [StructLayout(LayoutKind.Sequential)]
        private struct ObjectAttributes
        {
            public uint Length;
            public IntPtr RootDirectory;
            public IntPtr ObjectName;
            public uint Attributes;
            public IntPtr SecurityDescriptor;
            public IntPtr SecurityQualityOfService;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct UnicodeString
        {
            public ushort Length;
            public ushort MaximumLength;
            public IntPtr Buffer;
        }

        [DllImport("advapi32.dll")]
        private static extern uint LsaOpenPolicy(IntPtr systemName,
            ref ObjectAttributes attributes, uint access, out IntPtr policy);
        [DllImport("advapi32.dll")]
        private static extern uint LsaAddAccountRights(IntPtr policy, byte[] sid,
            [In] UnicodeString[] rights, uint count);
        [DllImport("advapi32.dll")]
        private static extern uint LsaEnumerateAccountRights(IntPtr policy, byte[] sid,
            out IntPtr rights, out uint count);
        [DllImport("advapi32.dll")]
        private static extern uint LsaNtStatusToWinError(uint status);
        [DllImport("advapi32.dll")]
        private static extern uint LsaClose(IntPtr policy);
        [DllImport("advapi32.dll")]
        private static extern uint LsaFreeMemory(IntPtr buffer);

        private static void Check(uint status)
        {
            if (status != 0)
                throw new Win32Exception((int)LsaNtStatusToWinError(status));
        }

        private static byte[] SidBytes(string accountSid)
        {
            SecurityIdentifier sid = new SecurityIdentifier(accountSid);
            byte[] bytes = new byte[sid.BinaryLength];
            sid.GetBinaryForm(bytes, 0);
            return bytes;
        }

        private static IntPtr Open(uint access)
        {
            ObjectAttributes attributes = new ObjectAttributes();
            attributes.Length = (uint)Marshal.SizeOf(typeof(ObjectAttributes));
            IntPtr policy;
            Check(LsaOpenPolicy(IntPtr.Zero, ref attributes, access, out policy));
            return policy;
        }

        private static bool HasRight(IntPtr policy, byte[] sid)
        {
            IntPtr buffer;
            uint count;
            uint status = LsaEnumerateAccountRights(policy, sid, out buffer, out count);
            // STATUS_OBJECT_NAME_NOT_FOUND: no explicit rights for this account yet.
            if (status == 0xC0000034) return false;
            Check(status);
            try
            {
                int size = Marshal.SizeOf(typeof(UnicodeString));
                for (uint i = 0; i < count; i++)
                {
                    UnicodeString value = (UnicodeString)Marshal.PtrToStructure(
                        new IntPtr(buffer.ToInt64() + i * size), typeof(UnicodeString));
                    if (String.Equals(Marshal.PtrToStringUni(value.Buffer, value.Length / 2),
                        Right, StringComparison.Ordinal)) return true;
                }
                return false;
            }
            finally { LsaFreeMemory(buffer); }
        }

        public static void Grant(string accountSid)
        {
            byte[] sid = SidBytes(accountSid);
            // POLICY_LOOKUP_NAMES | POLICY_CREATE_ACCOUNT; no replacement of policy.
            IntPtr policy = Open(0x00000810);
            try
            {
                if (!HasRight(policy, sid))
                {
                    UnicodeString value = new UnicodeString();
                    value.Length = (ushort)(Right.Length * 2);
                    value.MaximumLength = (ushort)(value.Length + 2);
                    value.Buffer = Marshal.StringToHGlobalUni(Right);
                    try { Check(LsaAddAccountRights(policy, sid, new[] { value }, 1)); }
                    finally { Marshal.FreeHGlobal(value.Buffer); }
                }
                if (!HasRight(policy, sid))
                    throw new InvalidOperationException("Symlink privilege verification failed.");
            }
            finally { LsaClose(policy); }
        }
    }
}
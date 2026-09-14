import { initializeApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";
import { getAuth } from "firebase/auth";
import { getStorage } from "firebase/storage";

const firebaseConfig = {
  apiKey: "AIzaSyC5WKSY9BlCgFAHi53GLENl-TRg5SQvTu0",
  authDomain: "areebakhan-transport.firebaseapp.com",
  projectId: "areebakhan-transport",
  storageBucket: "areebakhan-transport.firebasestorage.app",
  messagingSenderId: "856962329109",
  appId: "1:856962329109:web:3ee6cb24205136e7233c1c",
};

const app = initializeApp(firebaseConfig);
const dbInstance = getFirestore(app);
const authInstance = getAuth(app);
const storageInstance = getStorage(app);

export { dbInstance as db, authInstance as auth, storageInstance as storage };
